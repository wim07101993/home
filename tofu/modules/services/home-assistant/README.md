# `modules/services/home-assistant`

Home Assistant and the Matter server on plop — the Debian box on the home LAN
with the USB radio attached.

plop is the last host into tofu and the only one with no reverse proxy: Home
Assistant is reached on `8123` over the tailnet directly. Its zitadel client
lives in `../../zitadel` rather than here, because it predates this module.

## The Matter data was in the wrong place

`plop/homeassistant/docker-compose.yaml` had a stray quote:

```yaml
- /docker-volumes/homeassistant/matterjs-server:/data"
```

So the bind landed on the literal path `/data"`, which nothing reads. The image
declares `VOLUME /data`, so docker quietly supplied an anonymous volume there
instead, and matter-js wrote to it from 2026-06-30 onwards. Found 2026-09-23:

```
anonymous volume   17 MB   certificates/ config/ ota/ server-1-fff1/ vendors/
intended bind       0 B    empty
```

That volume held the server's certificates and its commissioned-device store.
**Nothing was commissioned at the time**, so it was discarded with the stack
rather than rescued — matter-js rebuilt an empty fabric against the correct
path on first start.

Had there been devices paired, they would all have needed re-commissioning:
`remove_volumes` defaults to true on `docker_container`, and a Portainer stack
delete can take anonymous volumes with it. The rescue would have been to copy
that volume's contents into `/docker-volumes/homeassistant/matterjs-server`
BEFORE deleting the stack.

This module mounts `/data`, spelled correctly, so the data now lands where the
path says it does. Worth checking after any future change to that container
that the directory is non-empty — an empty one means it has silently gone back
to an anonymous volume.

## What the cutover does not carry across

**`pids: 99`.** The compose stack set a cgroup PidsLimit on both containers.
`kreuzwerker/docker` has no attribute for it — its `ulimit` block sets
per-process rlimits, which is a different mechanism — so both containers lose a
fork-bomb guard they had. Recorded here rather than silently dropped.

**The container name.** `homeassistant-homeassistant-1` becomes
`home-assistant`. Nothing depends on it: Home Assistant is reached on the host
port and matter-js is on host networking.

## Host state this module does not own

`/docker-volumes/homeassistant/config` is Home Assistant's own directory —
automations, the device registry, secrets, and the sqlite recorder database. It
writes to it itself, so it cannot be generated from here.
`plop/homeassistant/configuration.yaml` in this repo is a reference COPY and
can drift from what is live.

Neither that directory nor the Matter data is backed up: kopia runs on mindy
and plop is not one of its sources.

## `/dev/ttyUSB0`

Passed through as a fixed path, which is not the same as a stable one — ttyUSB
numbering follows probe order, so adding another USB serial device can renumber
it and hand Home Assistant the wrong radio. `/dev/serial/by-id/...` is the
stable spelling; switching needs the id read off plop and is worth doing on its
own.

## configuration.yaml is generated

`configuration.yaml.tftpl` is rendered by tofu and uploaded on every container
create. It is a template rather than a copy because it carries the OIDC client
id and secret.

The old arrangement was worse than untracked: `plop/homeassistant/configuration.yaml`
held **placeholders** (`CLIENT_ID`, `CLIENT_SECRET`) because this repo is
public, and the real values were typed in by hand on plop. So the file in git
described something that had never run, and the file that ran belonged to
nobody. Delete the repo copy; this template supersedes it.

Verified 2026-09-23: an `upload` to a path under a DIRECTORY bind mount lands
on the host, rather than being shadowed by the mount. (A bind of the file
itself would shadow it — that distinction is why this was tested rather than
assumed.) Home Assistant never rewrites `configuration.yaml` itself; it writes
`.storage/` and the recorder database, so nothing of its own is lost. Anything
hand-edited on plop IS lost on the next apply, which is the intended trade.

## APPLYING THIS PERFORMS THE ZITADEL CUTOVER

The live config was using client id `345240228618895363` — the OLD,
pre-rebuild application, which tofu does not manage. The template injects
`zitadel_application_oidc.this.client_id`, a different app. Applying therefore
switches Home Assistant's login to the tofu-managed client.

**`has_project_check = true` on the `home` project.** Without a user grant on
that project, a person cannot obtain a token for the app at all — the login
fails rather than degrades. Before applying, confirm in the zitadel console
that the `home` project has grants for everyone who logs in to Home Assistant.
`modules/zitadel/README.md` lists recreating those grants as a pending step for
exactly this reason.

The user ids (`sub`) are unchanged, because the orgs and users were never
rebuilt — so accounts map across and nobody gets a fresh, empty profile.

If it does go wrong, recovery is local: Home Assistant's own username/password
login still works from a `trusted_ips` network, which is what `block_login`
plus those CIDRs are for.

## The client secret in the old file should be rotated

The secret that was live in `/docker-volumes/homeassistant/config/configuration.yaml`
was read during this migration and is therefore in a session transcript. It
belongs to the old application, which this cutover stops using — but that app
still exists in zitadel until it is deleted, so deleting it (or rotating its
secret) is the thing that actually retires the credential.
