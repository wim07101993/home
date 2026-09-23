# `modules/services/immich`

photos.wvl.app. Four containers, an NFS library from samson, and immich's own
pgvector/vchord postgres on mindy:5434 — a separate cluster from the shared
`db` the other services use.

## The database credential

Until 2026-09-23 immich connected as `postgres`, the cluster's bootstrap
superuser, with a password adopted into state and marked `ignore_changes = all`.
That made it the one credential in the estate that could not be rotated by
tofu, for a reason worth stating plainly:

**`POSTGRES_PASSWORD` is read by initdb and only by initdb, on an empty data
directory.** tofu could define the superuser password on the day a cluster was
born and never again — so on this cluster, which predates tofu, setting that
variable changed nothing at all. The value in the config and the value on the
server were free to disagree, silently.

Both roles are now tofu-owned:

| | role | password | rotation |
|---|---|---|---|
| admin | `postgres` | `var.immich_pg_superuser_password` — supplied | change the value, apply; the container applies it on start |
| app | `immich` | `module.immich.random_password.db` — generated | `tofu apply -replace='module.immich.random_password.db'` |

## Why the superuser password is still supplied

The container can set its own password — the image's generated `pg_hba.conf`
has `local all all trust`, so a connection over the unix socket *inside* the
container needs none. `assert-superuser-password.sh` uses that on every start.

So making it a `random_password` looks like it should work. It does not, and
the failure is flat:

```
Error: error connecting to PostgreSQL server ...
password authentication failed for user "postgres" (28P01)
  with module.immich.postgresql_role.this
```

**A provider is configured at plan time.** A `random_password` that has not
been created yet — or that `-replace` is about to regenerate — has an unknown
`result`, so the provider gets nothing and the plan dies before it can create
the thing that would fix it. Tried on 2026-09-23; this is the error it gives.

Getting past that needs an authentication path that does not use this password:
a second stable role for the provider, or client certificates. Neither is worth
it for one cluster.

**What the wrapper did buy** is that `var.immich_pg_superuser_password` is now
*enforced*. Change it, apply, and the cluster agrees — no `docker exec … ALTER
USER`. Previously tofu carried the value and had no way to make it true, so it
and the server could disagree silently and forever.

The ordering still matters, and is made explicit rather than hoped for:

```
var changes  ->  container replaced  ->  wrapper ALTERs  ->  marker file
             ->  healthcheck passes  ->  wait=true returns
             ->  provider connects   ->  postgresql_role.immich
```

The healthcheck requires the marker the wrapper writes only after a successful
`ALTER`, `wait = true` blocks the apply on it, and `postgresql_role.this` has
`depends_on = [docker_container.postgres]`. By the time anything asks the
provider for a connection, the cluster already carries the new password.

**The wrapper must never stop postgres from starting.** The assertion runs in
the background and a failure is logged, not fatal; postgres is `exec`'d so it
keeps PID 1. A cluster that will not boot because a password helper had a bad
day is far worse than a password one rotation behind. If the `ALTER` fails the
container goes unhealthy, the apply fails, and the cluster keeps its previous
password — recoverable, because the local socket is `trust` and there is root
SSH to the host.

bumba and mindy still supply their superuser passwords by hand. Their postgres
containers have no such wrapper yet. That is a gap to close, not a principle —
and bumba is deliberately last, because it holds this layer's own state
backend.

## Why `immich` is a superuser

Every other service here gets a least-privilege role. This one does not, and
that is a decision rather than an oversight.

Immich's documented non-superuser mode requires, after any vchord bump, a
manual:

```sql
ALTER EXTENSION vchord UPDATE;
REINDEX INDEX face_index;
REINDEX INDEX clip_index;
```

and disables immich's built-in backup, which uses `pg_dumpall`. That trades a
rare manual step — rotation — for a recurring one at every upgrade, on an
estate whose two worst incidents were both silent failures of things that
needed manual attention and did not get it.

The `immich` role has exactly the privileges the service already had, so this
is not a widening. It is the same access under a name tofu can rotate.

Objects stay owned by `postgres`: a superuser bypasses ownership checks, so no
`REASSIGN OWNED` across 66 tables and 8 extensions was needed.

databasus is unaffected — it backs this cluster up as its own
`databasus-*` role, which is not a superuser and does not use `pg_dumpall`.

## Migrating to it (2026-09-23)

Two applies. The first split the roles: `immich` created as a superuser with a
generated password, containers repointed at it, the old superuser password
captured out of state into `TF_VAR_immich_pg_superuser_password` first. The
second added the wrapper.

Three bugs were caught before or during that, all worth keeping:

**`psql -c` does not interpolate variables.** The wrapper first ran
`psql -c "ALTER USER postgres PASSWORD :'v'"`; the server received the literal
`:'v'` and answered `syntax error at or near ":"`. Postgres started normally
and the only symptom was one line in the log — a password rotation that
silently stopped happening. Caught by running the script against `postgres:17`
locally. It reads from stdin now, where interpolation does apply.

**This image does not boot `docker-entrypoint.sh`.** It boots
`immich-docker-entrypoint.sh`, which installs the tuned `postgresql.conf` from
a template, substitutes `PGDATA` and sources `set-env.sh`. The wrapper exec'd
the inner one directly, and `command` was reduced to `["postgres"]`, dropping
`-c config_file=/etc/postgresql/postgresql.conf`. Either alone loses
`shared_preload_libraries = vchord.so, vectors.so` — the cluster comes up,
looks healthy, and immich's vector extensions are gone. Caught by the plan
diff, which showed the image's real entrypoint and CMD being overwritten. The
wrapper now chains through `$REAL_ENTRYPOINT`.

**The image's healthcheck was being discarded** for a bare `pg_isready`. It is
ANDed with the marker file now, not replaced.

Verified in the local preflight: a changed password takes effect and the old
one is refused; a password containing `"`, `'`, `$`, `;` and a backslash
round-trips intact; a missing password file leaves postgres serving with the
container unhealthy; PID 1 is `postgres`, so signals still reach it.
