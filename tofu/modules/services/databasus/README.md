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
