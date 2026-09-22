# `modules/services/zitadel`

The identity provider for everything. `auth.wvl.app`, on bumba.

Zitadel v4 behind traefik, plus its loginV2 UI. Cut over from a portainer git
stack on 2026-09-18; the stack and `home-eu-central-1/zitadel/` are gone.

Not to be confused with [`../../zitadel`](../../zitadel/README.md), which
configures what is INSIDE zitadel — organisations, projects, roles and
applications. This module is the deployment; that one is the contents.

## Where each file comes from now

| file | source | why |
|---|---|---|
| `/zitadel-config.yaml` | **uploaded** from `./zitadel-config.yaml` | no secrets |
| `/run/secrets/zitadel_secrets.yaml` | **generated** from [`../../databases`](../../databases/README.md) | tofu owns both roles and their passwords |
| `/run/secrets/zitadel_masterkey` | **uploaded** from `var.masterkey` | see below |
| `/zitadel-init-steps.yaml` | host bind, `/docker-volumes/zitadel/` | bootstrap-only, holds the original admin password |
| `/login-client` | host bind, `/docker-volumes/zitadel/` | zitadel WRITES the PAT here; the login UI reads it |

Before this, all five were hand-maintained host files with stale copies in git —
and the copies had drifted: the repo said `Log.Level: 'info'` and carried
database usernames, the running config said `'Debug'` and carried neither.

## The masterkey

32 bytes. Every encrypted value in the database — IdP client secrets, machine
keys, the SMTP password — is unreadable without it. There is no reset.

It lived in exactly one place until 2026-09-18: `/docker-volumes/zitadel/` on
bumba, which **nothing backs up** — no cron, no kopia/restic/borg, no Hetzner
snapshots. It is now also in `secrets.auto.tfvars` and in the encrypted state.
Note the limit: state lives in postgres *on bumba*, so against that disk dying
the only copy that helps is the one on the laptop.

A wrong masterkey does not fail loudly. Zitadel starts and then cannot decrypt.
After any change here, **sign in** — startup alone does not prove it.

## Bringing this up somewhere new

1. `tofu apply` creates the database, both roles, the network and both
   containers.
2. Place `init-steps.yaml` and the `login-client/` directory on the host.
3. Put the masterkey in `secrets.auto.tfvars`. Without the original, the
   database is unreadable and this is a rebuild, not a restore.
4. `start-from-init` handles the rest; the init steps are no-ops against an
   existing instance.

## Ordering: the trap this hit twice

`tofu apply` refreshes **everything** before creating anything, and the zitadel
PROVIDER talks to `auth.wvl.app`. With the containers gone, refresh fails with
502 and the apply never reaches the resources that would fix it:

```
tofu apply -target=module.zitadel_server     # then a full apply
```

`depends_on` orders creation, not refresh, so it does not help here. Same shape
as the postgres note in [`../../../providers.tf`](../../../providers.tf).

## Still open

**`zitadel_root` is a postgres superuser.** Zitadel needs elevated rights for
the migrations it runs at boot; it may not need superuser forever. Worth
checking against zitadel's documented requirements rather than leaving the
status quo as an implicit decision. Preserved deliberately on adoption — see
[`./database.tf`](./database.tf) -- moved into this module on 2026-09-22.

**`Log.Level: 'Debug'`** in `zitadel-config.yaml`, left from debugging. bumba is
a cpx11 with 2 GB of RAM and this is the noisiest thing on it. One-line change,
deliberately not bundled into the cutover.

**`deploy.resources.limits.pids: 99`** did not survive — kreuzwerker/docker has
no `pids_limit`, and `ulimit { name = "nproc" }` is not a substitute (per-UID
rlimit, not per-container).

**Ports 3001/3002 publish on `0.0.0.0`.** Not an exposure: the Hetzner firewall
allows only ICMP, 80 and 443 inbound, and SSH itself only works over Tailscale.
Binding them to the tailnet address, as [`../gatus`](../gatus) does, would be
defence in depth.

## Corrected

The old readme said *"Everything runs on loginV1"* and suggested the login
container might be removable. That is **wrong**: the instance carries
`login_v2 = {"required": true}` (set 2025-10-03,
`projections.instance_features5`), so every application goes through the loginV2
container regardless of its per-app `login_version`. Removing it would take down
every login. Verified 2026-09-17 while chasing a passkey failure.
