# databasus (samson)

The database backup tool. Dumps postgres on bumba and mindy on a schedule.

## SSH

Key auth as `root`, installed 2026-09-19 — the same shape as bumba and mindy.

A non-root route was considered (`wim` in the `docker` group) and not taken. It
is worth recording why it would not have been a security win: **the docker group
is root-equivalent**, since a member can start a privileged container
bind-mounting `/`. It buys no root login over SSH and better attribution, not a
privilege boundary.

The provider is already wired in `tofu/providers.tf`. Note that a docker
provider which cannot dial its host fails `tofu plan` for the ENTIRE root
module, so samson being reachable is now a hard dependency of every plan.

In `tofu/variables.tf`:

```hcl
variable "samson_addr" {
  type        = string
  description = "samson's TAILNET address."
}
```

In `tofu/main.tf`:

```hcl
module "databasus" {
  source = "./modules/services/databasus"

  providers = {
    docker = docker.samson
  }
}
```

Leave this unwired until SSH works. A configured provider that cannot reach its
host fails `tofu plan` for the whole root module, not just this part of it.

## Cutover procedure

This is a cutover, not an import: portainer must stop managing the container
before tofu starts, or both will fight over it every day.

1. **Delete the stack in portainer on samson.** Not just stop it — a stopped
   git stack is redeployed on the next poll. Portainer redeploys every stack
   from git daily (`samson/incidents/2026-08-06-array-overheating.md`).
2. Confirm the container is gone: `docker ps -a | grep databasus`.
3. Confirm `/docker-volumes/backup-server/databasus/data` still exists and is
   not empty. The stack deletion must not take the data with it.
4. `tofu apply`.
5. Open the UI on port 4005 and confirm the **schedules and targets are still
   there**. A container that starts is not evidence: an empty data directory
   produces a perfectly healthy databasus with nothing configured.
6. Wait for one scheduled run and confirm a dump lands.

## The compose file is already deleted

`samson/backup-server/docker-compose.yaml` was removed in `f052970`
(2026-09-18), before this module existed. If the portainer stack is git-backed
against this repo, that stack now has no compose file to redeploy from.

Restore it, or complete the cutover above. Do not leave it as it is: the failure
mode is that database backups stop, quietly, which is exactly what happened in
August.

## Still outside tofu

- **The mailgun credential.** databasus has its own account for alert mail
  (`tofu/modules/mailgun/main.tf`). Add it as a fourth resource there when this
  moves — do not reuse another service's credential.
- **plex**, the other compose container on samson.

## Why the CONTAINER is in tofu but its CONFIGURATION is not

Decided 2026-09-19: databasus stays, and its backup targets, schedules,
retention and notifiers are configured by hand in the UI.

**There is no config file that can hold them.** `.env.example` upstream covers
only runtime plumbing — databasus's own DSN, goose migrations, log level,
OpenTelemetry, OAuth client ids. Every backup target lives in its embedded
postgres under `data/pgdata`, reachable only through the UI or the REST API.
That is why the compose stack this replaced was four lines with no environment
block: there was nothing to put in one.

A community provider exists (`pkerspe/databasus`, in the OpenTofu registry) and
covers workspaces, postgres databases, storages and backup configs. It was
considered and declined for now:

- its compatibility table pins v0.9.x to databasus **v3.45.0**; we run **v3.51.0**
- `backup_config` has no `ImportState`, so existing schedules could not be
  adopted — only recreated, with a retention policy attached
- upstream does not merely not support it, they discourage IaC for this tool:
  "not in line with their goals"

Revisit if databasus ever ships declarative config.

## THE BACKUPS CAN FAIL SILENTLY, AND DID

On 2026-09-19, three of five databases had been writing **64-byte** backup files
for one to three days:

| database    | last good backup | first empty |
|-------------|------------------|-------------|
| memos       | 2026-09-16       | 2026-09-17  |
| kitchen-owl | 2026-09-17       | 2026-09-18  |
| score       | 2026-09-18       | 2026-09-19  |

Cause: those databases moved from bumba to mindy during the database
consolidation, and databasus's targets still pointed at the old host — and at
port 5433, where mindy publishes 5432. `score` retried three times per run and
wrote a 64-byte file each time.

Nothing surfaced it. The files existed, were timestamped, and were counted as
completed backups. Checking that a backup file EXISTS is not a check; the newest
dump per database has to be verified for **size and age**.

Note also that databasus advertises restore verification, and it did not catch a
completely empty dump across three days.

Because the configuration is manual, that monitoring is the only thing standing
between a moved database and silent data loss. It belongs in gatus, using the
same external-push pattern as the kopia heartbeat (see modules/services/gatus).

## The check that was missing (2026-09-22)

Built. `check-backups.sh` runs beside databasus on samson and pushes one gatus
external endpoint per database, hourly, reading the backups directory
read-only.

A database reports **down** when the newest dump is older than 26h, when it is
under `min_bytes`, or when nothing has pushed at all — the last covered by
gatus's own heartbeat, which is what catches the checker dying.

Endpoint names are `backups_databasus-<key>` and the keys come from
`var.monitored` here. They must match the `external-endpoints` in
`../gatus/config.yaml`; nothing enforces it, and a mismatch reads as an
endpoint that is permanently down.

### What the state of things actually was

Re-examined on 2026-09-22, and it was worse than the table above records.
`kitchenowl`, `memos` and `score` had **no target configured at all** — no rows
in databasus's `databases` table, no backup config, no dump files. Only Immich
and zitadel were being backed up, and both were current, which is why the UI
looked fine. All five are configured now.

Two `databasus-*` roles on bumba's postgres were left behind by targets deleted
at some point before that, and have been dropped.

### Why it reads files instead of asking databasus

databasus has a webhook notifier that would have been less work. It can only
report what databasus believes, and both failures this estate has had were
invisible from there: a database with no target configured produces no failure
to notify about, and the 64-byte dumps were known to databasus — it wrote no
`.metadata` sidecar beside them — without that reaching anyone.

Age and size are properties of the artifact, which is the thing being relied on
when it matters.

### What it still does not check

That a dump **restores**. A file truncated at 60% passes both conditions.
Nothing short of restoring into a scratch database catches that, and databasus's
own restore verification did not catch a completely empty dump across three
days, so it is not a substitute.

### The dumps exist in one place

Storage is `Local`, on samson. kopia runs on mindy against photos, audio and
documents — not against samson. As of 2026-09-22 no second copy of these dumps
has been found; the OMV config was only grepped shallowly, so confirm before
relying on that either way. If it holds, losing samson loses every database
backup, and none of the monitoring above would say a word about it.
