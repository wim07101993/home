# IaC plan: OpenTofu + NixOS

Design notes from 2026-09-12. Nothing here is implemented yet except the
existing [`terraform` branch](https://github.com/wim07101993/home/tree/terraform).

Prompted by the array incident ([
`samson/incidents/2026-08-06-array-overheating.md`](../samson/incidents/2026-08-06-array-overheating.md)),
whose root causes were all *invisible state*: a stock cron job nobody knew
existed, a documented manual step that was never run, a mount that silently
failed, SMART data nothing was reading.

## The reframe that shapes everything

**None of the 2026-08/09 failures were caused by a lack of IaC.**

| failure                       | cause                                                                                                                        |
|-------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| fan never ran for 5 months    | physical                                                                                                                     |
| kopia dead 5 weeks            | **caused by** GitOps: a committed compose change auto-deployed while its manual prerequisite (cert generation) was never run |
| scrub broke the shutdown      | stock OMV `cron.monthly` job, invisible to `/etc/cron.d` and `systemctl list-timers`                                         |
| `audio-archive` never mounted | missing mountpoint directory, failed silently                                                                                |

More automatic deployment, without encoding prerequisites, makes the second one *worse*. The goals are **change
visibility** and **encoded manual steps** — not
automation for its own sake.

---

## Layering

Three layers, and the boundary between them is the important part.

| layer              | what                                               | tool                                         |
|--------------------|----------------------------------------------------|----------------------------------------------|
| **infrastructure** | Hetzner servers, volumes, firewalls, DNS, SSH keys | **OpenTofu**                                 |
| **machine**        | OS, packages, mounts, NFS, smartd, btrbk, users    | **NixOS** (local) / Ansible (cloud, for now) |
| **workload**       | containers, OIDC clients, DB roles                 | **OpenTofu**                                 |

OpenTofu owns what has an **API**. NixOS owns what has a **filesystem**.
A btrfs array has no API; a Zitadel OIDC client has no filesystem.

### Why OpenTofu rather than Terraform

Terraform moved to BSL in 2023. OpenTofu is the drop-in open fork. The existing
branch already uses a `tofu/` directory, so this is settled.

---

## Decisions

| decision                                                  | rationale                                                                                                                                                                          |
|-----------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **OpenTofu for the workload layer**, not just infra       | The Zitadel + PostgreSQL providers express things compose cannot (see below). Not a 1:1 compose translation.                                                                       |
| **OpenTofu on samson too**, for plex + databasus          | Marginal on its own merits — two trouble-free containers. But "everything is OpenTofu except these two" is worse than a little redundancy. Consistency wins for a single operator. |
| **NixOS on samson and plop**                              | Local machines; the layer that actually broke is the one NixOS owns.                                                                                                               |
| **Hetzner servers stay Debian initially**                 | One migration at a time. Revisit after samson is stable.                                                                                                                           |
| **Keep compose+portainer until a host is fully migrated** | Cut over per host, never half.                                                                                                                                                     |

### Rejected

- **Terraform for containers as a naive compose rewrite** — would lose dependabot,
  fight portainer for ownership, and need the Docker API exposed. The actual
  design avoids this (below).
- **Stretching one Docker Swarm across sites.** mindy is at Hetzner; samson and
  plop are at home behind a residential line. Overlay networks and swarm raft
  over a WAN is the NFS-over-WAN mistake wearing a different hat. **One swarm per
  host, or none.**
- **Fighting OMV with Ansible.** OMV regenerates `/etc/exports`, parts of
  `/etc/fstab`, Samba and SMART settings from its own config via Salt. Either
  respect the boundary or remove OMV. NixOS removes it.

---

## The workload layer: why it earns its place

From the `terraform` branch, `tofu/modules/file-browser/other_resources.tf`:

```
zitadel_application_oidc.filebrowser  ->  client_id
postgresql_role.filebrowser           ->  password
            | both injected via templatefile into
docker_secret.filebrowser_config      ->  mounted into the service
```

The OIDC client, the database role, the config file and the container are **one
dependency graph**. Compose cannot express any of it — the OIDC client gets
clicked into Zitadel by hand and the client ID pasted into a config file.

It also removes the secrets problem entirely: `random_password` ->
`docker_secret` means **no secrets in git**, and no placeholder files to copy and
fill in.

### Issues to fix before first apply

**Critical**

1. **State contains every secret** — Zitadel masterkey, all DB passwords.
   The repo is public and has no `.gitignore`.
   **Resolved 2026-09-16 for the infra layer:** root `.gitignore` covers
   `*.tfstate*` and `*.tfvars`, and `tofu/providers.tf` carries an
   `encryption` block so state and plan files are ciphertext at rest wherever
   they land. The workload layer must copy both before its first apply — it is
   the layer that actually holds the masterkey.
2. **Providers cannot depend on resources.** This fails on a clean apply:
   ```hcl
   provider "postgresql" {
     password = random_password.db_password.result  # unknown at provider-config time
     host     = "db"                                # overlay network name, unresolvable from the host
   }
   ```
   Provider config is evaluated before the resource graph. The same wall applies
   to the Zitadel provider needing a service-account key that does not exist
   until Zitadel has booted once (already flagged in the branch's own comments).

   Fix: **stages with separate state**, wired by `terraform_remote_state`:

   | stage | contains | provider needs |
      |---|---|---|
   | `00-platform` | swarm networks, db service + secret | docker only |
   | `10-data` | postgres roles, databases | db reachable on `localhost:5432` |
   | `20-identity` | zitadel service, init steps | docker + postgres |
   | `30-apps` | zitadel org/project/OIDC apps, all other services | zitadel API + machine key |

   For stage 30: have Zitadel write a service-account key at first boot (`FirstInstance.MachineKeyPath` in the existing
   `zitadel_init_steps`), then
   point the provider at it with `jwt_profile_file`.

**Decide before going further**

3. **Swarm.** `docker_service`, `docker_secret` and `driver = "overlay"` all
   require swarm mode; the hosts run plain docker + portainer today. Single-node
   swarm is stable and is the only route to real `docker_secret`.
   samson needs **no** secrets (plex is PUID/PGID/TZ, databasus is a bind mount),
   so plain `docker_container` is fine there — no swarm on that box.
4. **Multi-host.** The branch has one `unix:///var/run/docker.sock` provider, but
   the modules mix hosts. Needs aliases:
   ```hcl
   provider "docker" { alias = "mindy", host = "ssh://root@100.127.106.121" }
   module "immich" { providers = { docker = docker.mindy } }
   ```
5. **The portainer cut.** Once OpenTofu owns a service, portainer's daily git
   redeploy of the same stack must stop or they reconcile against each other.
   Migrate one host fully, delete its portainer stacks, then move on.
6. **Dependabot goes blind.** It only parses `docker-compose.yaml`; image strings
   in HCL are invisible to it. **Renovate** has a `terraform` manager and docker
   image detection — switch before losing the upgrade flow on seven stacks.

   **Done 2026-09-16:** [`renovate.json`](../renovate.json) at the repo root.
   Reading the old config sharpened the case: `.github/dependabot.yml` listed
   **six** directories by hand, all under `mindy/`, so `kitchen-owl`, `memo`,
   `uptime-kuma` and **everything** under `home-eu-central-1/`, `plop/` and
   `samson/` were never covered. That is the actual reason bumba's traefik sat
   on `v3.7.10` while mindy's reached `v3.7.13` — not drift, absence.

   Renovate scans the repo rather than a list, so the gap closes as a side
   effect, and it reads OpenTofu HCL as well. Image strings held in a variable
   are found via a `# renovate: datasource=docker depName=...` annotation;
   provider constraints in `required_providers` are picked up by the built-in
   manager without help.

   **`automerge` is `false` and must stay that way.** Portainer redeploys its
   git stacks daily, so merging here *is* deploying — and a merge whose manual
   prerequisite was never run is what killed kopia for five weeks in 2026-08.
   Delete `dependabot.yml` once the first Renovate PRs look right; running both
   produces duplicates.

**Minor**

- `zitadel_init_steps` contains a literal `Password: Password1234!` in a public
  repo. Bootstrap-only with `PasswordChangeRequired: true`, so small blast
  radius, but it should be a `random_password`.
- Swarm secrets are immutable, so content changes need a new name. The `_v1`
  suffixes anticipate this; consider
  `name = "zitadel_config_${substr(sha256(data), 0, 8)}"` so it rotates
  automatically instead of failing until someone remembers to bump it.

---

## NixOS

### Why samson specifically

Every OMV-related problem in the incident is one NixOS structurally does not have:

| what happened                                  | on NixOS                                                            |
|------------------------------------------------|---------------------------------------------------------------------|
| stock monthly scrub cron nobody knew existed   | every timer is a line in the config                                 |
| `/etc/exports` auto-generated, unversionable   | `services.nfs.server.exports` is a string in git                    |
| SMART monitoring never configured              | `services.smartd`, declared                                         |
| btrbk postinst silently enabled a daily timer  | modules do not enable timers behind your back                       |
| system update -> broken shutdown               | `nixos-rebuild --rollback`, or pick the previous generation at boot |
| `chmod -x` on a dpkg file that upgrades revert | config is the source of truth; nothing drifts back                  |

### What makes it feasible

**samson's OS is on a separate disk.** `sda` is a 119 GB SSD holding `/`; the
array is four independent drives; the backup drive is USB. Migration means
reinstalling `sda` and importing the array by UUID — the data is never touched,
and the old SSD is a five-minute rollback.

### Sketch

```nix
{ config, pkgs, ... }:
let
  arrayUuid  = "25d0f3ec-68a9-4ce0-891e-0966088e5300";
  backupUuid = "fbc74530-17f6-4f65-9e40-f4b2537086ca";
  mindy      = "100.127.106.121";
in {
  networking.hostName = "samson";

  fileSystems."/srv/array" = {
    device = "/dev/disk/by-uuid/${arrayUuid}";
    fsType = "btrfs";
    options = [ "noatime" ];
  };

  # off-site drive: present ~6% of the time, must never block boot
  fileSystems."/mnt/backup-14t" = {
    device = "/dev/disk/by-uuid/${backupUuid}";
    fsType = "btrfs";
    options = [ "noauto" "nofail" "noatime" ];
  };

  services.nfs.server = {
    enable = true;
    exports = ''
      /export/photos ${mindy}(rw,sync,no_root_squash,insecure,subtree_check)
      /export/media  ${mindy}(ro,sync,no_root_squash,insecure,subtree_check)
      # ...
    '';
  };

  # the prevention item outstanding since August
  services.smartd = {
    enable = true;
    autodetect = true;
    defaults.monitored = "-a -W 0,50,55 -m wim@zitadel.com";
    notifications.mail = { enable = true; recipient = "wim@zitadel.com"; };
  };

  services.btrbk.instances.offsite = {
    onCalendar = null;          # explicit: drive is off-site, runs are manual
    settings = { /* see samson/backup/btrbk.conf */ };
  };

  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [ "/srv/array" ];
    interval = "monthly";
  };

  virtualisation.docker.enable = true;   # OpenTofu owns the containers
  services.tailscale.enable = true;
}
```

Note what is in there: the 55 °C SMART threshold and email that has been
outstanding since August, the scrub schedule as one visible line (flip it in a
commit rather than `chmod -x` on a dpkg file), and `onCalendar = null` making
"no timer" a decision rather than something you had to notice and undo.

### Costs, honestly

- **The OMV web UI is replaced with nothing.** Shared-folder management, disk
  dashboard, ACL editor — gone.
- **Real learning curve.** Bounded — most of the config is option-setting — but
  the first week is frustrating.
- **Docker stays slightly awkward**, though not under this plan: NixOS provides
  the daemon, OpenTofu owns the containers.

---

## OpenTofu + NixOS together

Standard integration is **`nixos-anywhere`** (nix-community), which ships
OpenTofu modules — kexecs into an installer over SSH, partitions with **`disko`**,
installs the flake. So `hcloud_server` -> NixOS installed -> deployed in one apply.

The common alternative is **OpenTofu for cloud resources only**, emitting an
inventory, then **colmena** or **deploy-rs** for the NixOS side. Two tools, but a
cleaner mental model and rollbacks stay where they belong.

### The friction point: who owns containers

NixOS can declare containers via `virtualisation.oci-containers`. **Don't.** The
value chain is:

```
zitadel_application_oidc -> client_id -> templatefile -> docker_secret -> service
```

If NixOS owns the service, that chain crosses a tool boundary and needs a
handoff (SOPS file, `sops-nix`, a rebuild trigger). **NixOS provides the docker
daemon; OpenTofu keeps the containers.** The graph stays one apply.

### Gotchas

- **OpenTofu triggering `nixos-rebuild` is slightly unnatural** — a
  `terraform_data` resource keyed on the flake output hash. A `--rollback` at 2am
  happens outside state, so the next plan shows drift. Main argument for colmena.
- **Never let both tools own the same resource type.** Write the boundary down,
  exactly as with OMV.
- **samson has no cloud API** — no server, volume or firewall object to manage.
  Its infra layer is empty; it is pure NixOS plus the docker provider.

---

## Adopting existing Hetzner servers — no rebuild required

**Concern:** the current Hetzner server types may no longer be orderable, so
recreating them is impossible.

**Neither layer requires recreating a server.** The docker provider connects to a *running* dockerd over SSH and does
not care how the host was built. And infra is
adopted with `import`, not recreation:

```hcl
import {
  to = hcloud_server.mindy
  id = "12345678"        # hcloud server list -o columns=id,name
}
```

Then `tofu plan -generate-config-out=generated.tf` writes the resource blocks
from the live API, rather than hand-transcribing forty attributes.

### The rule that matters

**After import, `tofu plan` must report "No changes".** A plan showing
`-/+ destroy and then create replacement` is the failure mode — and on a
deprecated server type the destroy is permanent.

```hcl
resource "hcloud_server" "mindy" {
  # ...
  lifecycle {
    prevent_destroy = true          # apply refuses to destroy, full stop
    ignore_changes = [
      image, # the creating image may no longer exist
      ssh_keys, # forces replacement in the hcloud provider
      user_data, # same
    ]
  }
}
```

Put `prevent_destroy = true` on every imported server on day one; remove it only
when deliberately replacing something. Attributes that force replacement are
roughly `image`, `location`/`datacenter`, `ssh_keys` and `user_data`.
`server_type` can usually be increased in place to an *available* type — what you
cannot do is go back to a deprecated one.

Check the actual state first:

```bash
hcloud server list -o columns=id,name,server_type,location,status
hcloud server-type list      # deprecated types are flagged
hcloud volume list
hcloud firewall list
```

### Provider coverage caveats

- `hetznercloud/hcloud` — official, solid for servers/volumes/firewalls/networks.
- **Hetzner DNS** is community-maintained; verify which provider is current
  before committing. 13 `wvl.app` records currently live in a web console:
  `auth drive photos office keuken memo score score-api partituren baby it-tools
  homepage traefik` (+ `status` once Uptime Kuma lands).
- **Storage Box** coverage has historically been weak (Robot API, not Cloud API).
  Verify before assuming it can be managed declaratively.

---

## Migration order

Rewritten 2026-09-17 to match what happened, which was not the order below.

### Done

1. **Full media copy to the 14 TB drive.**
2. **Array surgery.** raid10 -> raid1 balance finished 2026-09-15; `WSD320VH`
   removed 2026-09-16 after 163,188 write errors during the balance; scrub
   completed 2026-09-17 reporting **no errors found** across 16.86 TiB, so every
   RAID1 chunk had two good copies and those failed writes were never
   acknowledged.
3. **Infra -> OpenTofu.** Five Hetzner resources adopted by `import`, planning
   clean. State in postgres on bumba, encrypted client-side.
4. **Databases -> OpenTofu.** `zitadel` and `score` adopted. Roles not yet.
5. **traefik -> OpenTofu**, both hosts. Cutover rather than adoption -- a
   compose-created container cannot be reproduced attribute-for-attribute.
   Routing moved from labels to the file provider, and the **docker socket is no
   longer mounted into either proxy**. `mindy/traefik/` and
   `home-eu-central-1/reverse-proxy/` deleted 2026-09-17; `git show` on the old
   paths is the rollback.
6. **Zitadel projects and applications -> OpenTofu.** A **rebuild**, not an
   adoption. Orgs and users are untouched, which is what keeps every OIDC `sub`
   stable.
7. **bumba's postgres -> OpenTofu.** The container holding zitadel's database,
   score's, and this layer's own state. Cutover ran with the backend
   temporarily disabled and state local, because an apply that recreates that
   container would otherwise have to write state to the database it just
   recreated.

   Two things worth carrying forward. `tofu apply` refreshes **everything**
   before creating anything, so with postgres down the refresh of the
   postgresql and zitadel providers fails and the apply never reaches the
   container that would fix it -- `-target` is the way through, and this is
   exactly the "exceptional situation" the targeting warning describes. And a
   wrong data path does not error: postgres builds an empty cluster beside the
   real one and reports itself healthy, so the check is `docker logs` for crash
   recovery rather than initdb.

### Still outstanding

8. **Cut the applications over** to the new zitadel client ids, then recreate
   ~25 user grants, then delete the old projects and the `dev` org.
9. **plop -> NixOS.**
10. **samson -> NixOS.**

### What the original order got wrong

It put OpenTofu last, after both NixOS migrations, and described it as
"via `import`, no rebuilds". Two corrections:

**OpenTofu came first, and that was right.** It needed no downtime for the
adoption work and no machine rebuilt. Sequencing it behind two OS migrations
would have delayed every benefit for no gain.

**Not everything could be imported.** Containers and Zitadel applications both
turned out to be rebuild-or-nothing -- the first because compose's creation
shape is not reproducible, the second because zitadel's import ids are composite
and `client_secret` cannot be read back. Adoption works for resources whose
every attribute is readable; it does not for resources holding a
write-only secret. That distinction is worth carrying into the NixOS work.

**Why the array still had to come first:** a NixOS migration means reinstalling
`sda` and re-importing the array. Doing that while the array still held a drive
at 2,016 pending sectors would have overlapped two risky operations, and a
failure would have been ambiguous.

**Why plop still precedes samson:** plop is the dev box. Learn NixOS, and
re-declaring NFS/smartd/shares by hand, where the cost of error is a restarted
Home Assistant rather than the family photo array. Four spare OptiPlexes are
available to rehearse samson's config on before swapping the real `sda`.

Capture before plop moves: Home Assistant's `configuration.yaml` and
`/docker-volumes/homeassistant/config`. NixOS manages the container, not HA's
internal state.

---

## Cheap win, independent of all of the above

`etckeeper` on samson — ten minutes, git-tracks `/etc`, auto-commits on every
apt run. It would have shown exactly when btrbk's timer appeared and what the
2026-09-11 system update changed. Costs nothing if NixOS later makes it
redundant.

Also worth enabling: **GitHub push protection** (Settings -> Code security) plus a
`gitleaks` pre-commit hook. The repo's secret files are all placeholders today,
but that is a discipline currently held by memory rather than enforced.

---

## Open questions

- [ ] Do the Hetzner servers eventually move to NixOS too, or stay Debian +
  Ansible?
- [ ] Swarm on mindy / home-eu-central-1: commit to it, or drop `docker_secret`
  and find another secret mechanism?
- [x] **State backend — decided 2026-09-16: `backend "pg"` on bumba, over
      Tailscale.** Reasoning and the rejected candidates are in
      [`tofu/README.md`](../tofu/README.md), "State backend".

      Short version: state goes where the things everything else depends on
      already live. bumba is the designated auth-and-database box, its postgres
      is reachable only over the tailnet, and the Hetzner Cloud Console means a
      locked-out tailnet is still recoverable from anywhere — which samson and
      plop cannot offer at all.

      Three properties the object-store options could not match: it is not
      internet-facing; it needs **no bootstrap**, because this postgres already
      exists and is not a resource in the state it holds; and advisory locking
      is real database locking rather than a conditional-write trick.

      Two gaps closed by hand rather than by the backend: a trigger gives
      per-apply state history (the backend overwrites one row), and the
      `tofu_state` role is created manually and must never be managed by the
      workload layer, or the credential for reading state ends up inside it.

      Client-side encryption stays regardless. It is what covers the copies
      nobody decides about — the Hetzner volume, the `pg_dump` to samson, the
      14 TB drive at the family.
- [ ] Does OMV's web UI need replacing on samson (Cockpit?), or is SSH enough?
