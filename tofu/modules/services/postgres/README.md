# `modules/services/postgres` — bumba's postgres

Holds zitadel's database, score's, and **this layer's own state**.

Cut over from the compose stack `database` on 2026-09-17;
`home-eu-central-1/database/` deleted the same day. `git show` on that path is
the rollback — and if you take it, `tofu state rm
module.postgres_bumba.docker_container.this` first, or portainer and tofu will
both own the same container.

## The value that matters most

```hcl
networks_advanced {
  aliases = ["db"]
}
```

`zitadel-config.yaml` sets `Database.postgres.Host: 'db'`, and score resolves
the same name. That is **not** the container name — it is the network alias
compose adds for the service, and compose gave it for free. `docker_container`
does not. Recreate without it and zitadel cannot reach its database, which
takes auth down for every service in the estate.

`database-db-1` is also an alias on the live network, but that one is the
container name and docker adds it automatically.

## Host files this expects

Neither is created by tofu; both must already exist on bumba.

| path | what |
|---|---|
| `/docker-volumes/db/data` | symlink to `/mnt/HC_Volume_103225027/db/data/` — the cluster |
| `/docker-volumes/db/db_password.txt` | one line: the postgres superuser password, no trailing newline issues |

The compose stack declared the second as a `secret`; without swarm that is a
read-only bind mount either way, so this module says so plainly. A placeholder
for it used to live at `home-eu-central-1/database/db_password.txt`; that
directory was deleted with the cutover, which is why the requirement is written
here instead.

## Recreating this container

Not a normal apply. The procedure is written above the `backend` block in
[`../../../providers.tf`](../../../providers.tf); the short version:

1. comment out the backend block, `tofu init -migrate-state` (state goes local)
2. `tofu apply -target=module.postgres_bumba`
3. check `docker logs` for crash recovery, **not** initdb
4. restore the backend block, `tofu init -migrate-state`
5. `rm terraform.tfstate*`

Two things that are not guessable:

**`tofu apply` refreshes everything before creating anything.** Both the
postgresql and zitadel providers need a live postgres, so with the container
gone the refresh fails and the apply never reaches the resource that would fix
it. `-target` is the way through — this is precisely the "exceptional
situation" the targeting warning describes.

**A wrong data path does not error.** `/docker-volumes/db/data` is a symlink to
`/mnt/HC_Volume_103225027/db/data/`. Point it somewhere else and postgres
quietly runs initdb, builds an empty cluster beside the real one, and reports
itself healthy. The log is the only check that catches it: crash recovery says
`redo lsn=...`, a fresh cluster says `initdb`.

## Deliberately not changed

`ports` binds `0.0.0.0`, like the compose stack did. The only thing keeping
postgres off the internet is `firewall-1`, which allows 80, 443 and icmp and
nothing else. Narrowing to `127.0.0.1` plus the tailnet address is a one-line
change here and would make that two independent layers — worth doing, but on
purpose and on its own, not bundled into a migration where a failure would be
ambiguous.
