# Zitadel

The identity provider for everything. `auth.wvl.app`, on bumba.

Zitadel v4, behind traefik. The **container** is still compose-managed; its
**projects, roles and applications** moved to OpenTofu on 2026-09-17 --
[`../../tofu/modules/zitadel/`](../../tofu/modules/zitadel/README.md).

## The files here are copies

Everything except `docker-compose.yaml` is mounted from
`/docker-volumes/zitadel/` on bumba, not from this directory. They are in git so
the intended contents are reviewable and recoverable; editing them changes
nothing until they are copied to the host.

| repo | host | container |
|---|---|---|
| `zitadel-config.yaml` | `/docker-volumes/zitadel/zitadel-config.yaml` | `/zitadel-config.yaml` |
| `init-steps.yaml` | `/docker-volumes/zitadel/init-steps.yaml` | `/zitadel-init-steps.yaml` |
| `zitadel_secrets.yaml` | `/docker-volumes/zitadel/zitadel_secrets.yaml` | `/run/secrets/...` |
| `zitadel_masterkey` | `/docker-volumes/zitadel/zitadel_masterkey` | `/run/secrets/...` |

## Bringing this up somewhere new

1. **A database and two roles.** `zitadel_root` (owner, currently a superuser --
   see below) and `zitadel_user`. The database is now declared in
   [`../../tofu/modules/postgres/`](../../tofu/modules/postgres/README.md); the
   roles are not yet.
2. **Place the four files above** on the host, with the placeholders replaced.
3. **The masterkey is 32 bytes and irreplaceable.** Every encrypted value in
   the database is unreadable without it. It existed in exactly one place
   until 2026-09-14, on a machine nobody could log into.
4. `start-from-init` handles the rest. It is idempotent -- the init steps are
   no-ops against an existing instance.

## Things worth fixing

**`zitadel-login:latest`** is the only unpinned image in the estate, and it is
the login UI for every service. Renovate cannot manage `latest`. Pin it to
match `zitadel:v4.17.3`.

**`zitadel_root` is a postgres superuser.** Zitadel needs elevated rights to
create its schema at first boot; it does not need superuser forever. Worth
checking against Zitadel's documented requirements rather than leaving the
status quo as an implicit decision.

**The `traefik.*` labels are inert.** Routing moved to the file provider in
[`../../tofu/modules/services/reverse-proxy/bumba/dynamic.yml`](../../tofu/modules/services/reverse-proxy/bumba/dynamic.yml)
and nothing reads container labels any more. Delete them next time this stack
is touched, so nobody edits one expecting an effect.

**The login container may be removable.** Everything runs on loginV1; the open
question is whether Zitadel's own Console does. Test by stopping
`zitadel-zitadel-login-1` and trying to log in -- reversible in seconds, and
definitive where the API is not. If it goes, delete the `login-client` machine
user too; its PAT does not expire until 2029.
