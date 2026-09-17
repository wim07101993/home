# `tofu/` — the estate at Hetzner, and bumba's postgres

One OpenTofu root module. **Adoption only** — nothing here is meant to create a
server, a volume or a Storage Box, ever. It does create databases and roles.

> **Status.**
> - Hetzner: five resources adopted 2026-09-16.
> - postgres: two databases adopted. Roles not yet — see the blockers below.
> - traefik on **both** hosts: cut over from compose 2026-09-17. Routing
>   centralised per host in `dynamic.yml`, docker socket no longer mounted
>   anywhere.
> - zitadel: 6 projects, 6 roles, 8 applications built fresh. Nothing cut over
>   yet -- see modules/zitadel/README.md.
> - bumba's postgres: cut over from compose 2026-09-17. It holds this state, so
>   the cutover ran with the backend disabled and state on the operator's
>   laptop -- the procedure is documented above the backend block in
>   providers.tf and must be repeated for any future recreation.
> - State in postgres on bumba, encrypted client-side, with per-apply history.

## Layout

```
tofu/
  providers.tf   the ONLY place providers are configured
  variables.tf   root variables, all fed by env.sh
  main.tf        two module blocks
  imports.tf     adoption record and outstanding imports
  moved.tf       one-time state renames from the merge -- deletable after apply
  modules/
    hetzner/        servers, volume, firewall, storage box -- adoption only
    postgres/       databases, and later roles
```

One root module, two child modules: **one state, one `init`, one `apply`**.
The directories are for reading, not for isolation — `tofu` only loads `.tf`
files from the root directory, so structure has to mean modules rather than
folders.

Neither child declares a `provider` block. They declare only which providers
they *use*, and inherit the root's configuration, so there is exactly one place
the Hetzner token and the postgres superuser password are wired in.

## Why this is one module

It was two root modules — `infra/` and `workload/` — and was merged on
2026-09-16.

The split bought one real thing: `infra/` could run on a **read-only** Hetzner
token indefinitely, because it never created anything, and a read-only token
physically cannot execute the replacement that would destroy a `cpx11` `fsn1`
no longer sells. Everything else it bought was weaker than it looked. "A
one-database change should not print a sixty-resource plan" is an argument from
human vigilance, and the thing actually protecting bumba is `prevent_destroy`,
which is mechanical.

Against that: two `init`s, two `env.sh`es, a Makefile that existed only to
paper over the split, and `terraform_remote_state` plumbing the moment anything
crossed. Friction paid daily, for a benefit that was mostly latent — and the
goal of this whole migration is *change visibility*, which a tool you run less
often does not deliver.

So: one state, and `prevent_destroy` carries the weight. The structural
clarity the split was really providing is kept by `modules/`, which costs
nothing at runtime. The hard blockers
that would have forced a split do not apply here, because this is brownfield
adoption rather than a clean apply — postgres already exists, so the provider
takes a static superuser password from the environment rather than a
`random_password`, and Zitadel is already running, so its machine key is a
one-time manual step rather than a stage boundary.

Splitting into separate root modules again would be `tofu state rm` plus an
`import` block per resource — not a one-way door either way.

samson and plop are **not** here and never will be. They have no cloud API —
no server, volume or firewall object to manage. Their layer is NixOS.


## Why adoption and not `create`

mindy and bumba run on server types that may no longer be orderable. A plan
reading `-/+ destroy and then create replacement` is not a slow apply, it is a
one-way door: the destroy succeeds and the create fails on a deprecated type.
The Storage Box is worse — it is one of the three copies of the family photos.

So the rule this whole directory exists to enforce:

> **After import, `tofu plan` must report "No changes".**
>
> Anything else is a bug in the config, not a change to apply.

## State holds secrets

`hcloud_storage_box` takes `password` as a **required** argument, so the
Storage Box password ends up in state. Two mechanisms cover that, and they
answer different questions:

| mechanism                             | question it answers                                   |
|---------------------------------------|-------------------------------------------------------|
| root [`.gitignore`](../.gitignore) | does state get committed to a public repo?            |
| `backend "pg"` on bumba               | can anyone on the internet reach it?                  |
| `encryption` block in `providers.tf`  | is it readable by whoever ends up with a copy anyway? |

The second is the one that matters once state stops living only on one laptop.
OpenTofu encrypts **client-side**, so the backend never sees plaintext — and
neither does anything downstream of it. That is the point: the row lands on
bumba's Hetzner volume, again in the `pg_dump` to samson, and again on the
14 TB drive at the family. Every one of those copies is ciphertext, and none
of them needed a decision of their own.

### The passphrase

`TF_VAR_state_passphrase`, minimum 16 characters — `pbkdf2` refuses anything
shorter.

It is read by the `encryption` block, which OpenTofu evaluates *before* the
resource graph exists, so it has to come from the environment and can never be
derived from anything else in the config. `env.sh` takes it from the
environment or prompts for it.

Losing it loses state. For an adoption-only layer that means re-running the
imports, not losing infrastructure — a bad afternoon, not a disaster. Keep it
somewhere a second person could reach it anyway.


### Plan files too

`plan { method = ... }` is not decoration. `tofu plan -out=tfplan` writes the
same secrets to disk, unencrypted, without it.

## State backend: postgres on bumba

`backend "pg"`, reached over Tailscale. Decided 2026-09-16.

### Why this one

| candidate                   | why not                                                                                                                                                                                                                                                                                                                                                                                                                             |
|-----------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| storage box                 | no backend speaks SMB/WebDAV/SFTP. `local` over a davfs2 or CIFS mount means a torn write on the one file with no second copy — and a silently-failing mount is already two of the four root causes in the 2026-08 incident.                                                                                                                                                                                                        |
| this repo, encrypted        | the repo is public. Ciphertext pushed there is out **permanently**, so estate security reduces forever to one passphrase against offline attack, and rotating it does not help — the Zitadel masterkey inside does not change when the state passphrase does. Worse, allowing it means negating `*.tfstate` in `.gitignore`, which is the backstop against committing *unencrypted* state — and `tofu state pull` writes plaintext. |
| Bitwarden attachment        | not a backend; only a wrapper around `local`. Attachments are immutable, so every push is delete-then-upload, with a window where no remote copy exists. No locking, no history, and `bw` needs an interactive `BW_SESSION`.                                                                                                                                                                                                        |
| R2 / Hetzner Object Storage | both work. Both are reachable from the whole internet, with an access key as the only barrier, and both would have to be **created by tofu before tofu could store the state describing them**. Hetzner additionally has no bucket resource in the hcloud provider, costs €5.99/month for a 50 KB file, and puts state in the same account as the infrastructure it documents.                                                      |
| samson or plop              | no out-of-band access. If a Tailscale node key expires while away from home, there is no console, no rescue mode, no way in until physically present. bumba has the Hetzner Cloud Console. Neither box runs postgres today either.                                                                                                                                                                                                  |

bumba wins on three counts. It is the box already designated to hold the things
everything else depends on — auth, and the database — so state living beside
them adds no new dependency. Its postgres is reachable only over Tailscale, so
the store is not internet-facing at all. And the Cloud Console means a
locked-out tailnet is recoverable from anywhere.

The cost is that `tofu plan` cannot read state unless Tailscale is up and bumba
is up. That is real but smaller than it sounds: **tofu is not the recovery
tool.** A down bumba is fixed from the Cloud Console, and `prevent_destroy`
means tofu could not rebuild it anyway.

### No bootstrap step

Worth stating because every other candidate needed one. This postgres already
exists and is **not** a resource in this state, so there is no chicken-and-egg,
no local-then-migrate dance, and no separate bootstrap root module. Configure
the backend and `tofu init`.

That stops being true for the workload layer, which *will* manage this postgres
— see "The one credential tofu must never manage" below.

### One-time setup

Three secrets. Pick them yourself — nothing here generates them, so whatever
you keep them in stays the single source of truth.

| variable | holds |
|---|---|
| `HCLOUD_TOKEN` | a **read-only** Cloud API token |
| `TF_VAR_state_passphrase` | the state encryption passphrase, 16+ chars |
| `TOFU_STATE_DB_PASSWORD` | the `tofu_state` postgres role's password |

`env.sh` takes each from the environment if it is set and prompts otherwise, so
there is no dependency on any particular vault. If you do use one, that is a
line in your own shell rc rather than something this repo requires:

```bash
export TF_VAR_state_passphrase="$(rbw get 'OpenTofu state')"     # or bw, pass, ...
```

`PG_CONN_STR` overrides `TOFU_STATE_DB_PASSWORD` entirely if you would rather
assemble the connection string yourself. `BUMBA_ADDR` skips the `tailscale ip`
lookup.

Then, in order:

```bash
./bootstrap-state-db.sh          # role + database on bumba. Idempotent.
. ./env.sh
tofu init                        # creates schema tofu_infra and its states table
./bootstrap-state-history.sh     # the trigger, which needs that table to exist
```

`bootstrap-state-db.sh` creates a dedicated **database**, not a schema inside an
application database, so a `DROP DATABASE` during app surgery cannot take state
with it — which is exactly what happened to `memos` on 2026-09-15.

It reaches bumba over ssh **by tailnet IP**, not by name: local host names carry
a `.home` suffix the resolver does not always apply, and `env.sh` has resolved
the address already. That also keeps the hop on the tailnet by construction
rather than by convention. `SSH_HOST=` overrides it with an ssh_config alias if
you prefer one.

### Connecting

`env.sh` builds `PG_CONN_STR`, resolving bumba through `tailscale ip -4` rather
than hardcoding an address (`BUMBA_ADDR` skips the lookup; `BUMBA_TS_HOST`
changes the device name). No secret is stored in the file, which is why it is
safe in a public repo.

It emits libpq **keyword/value** form rather than a `postgres://` URI. A URI
needs the password percent-encoded, and an unescaped `@` or `/` in it does not
error — it silently produces a connection string pointing somewhere else. Both
`psql` and the pg backend accept either form.

`sslmode=disable` is deliberate: this postgres has no TLS certificates, and the
transport is already a WireGuard tunnel. It is not a shortcut, but it *is* the
reason the connection must never be made over anything but the tailnet.


**Know what is actually protecting it.**
`home-eu-central-1/database/docker-compose.yaml` publishes `"5432:5432"`, which
binds `0.0.0.0` — postgres listens on bumba's public IPv4 and IPv6. The only
thing keeping it off the internet is `firewall-1` (`10051212`), confirmed
2026-09-16 to hold exactly three allow rules — tcp/80, tcp/443, icmp — from
`0.0.0.0/0` and `::/0`. Hetzner default-denies inbound, so 5432 is dropped on
both address families. `nc -vz 5.75.247.152 5432` times out rather than being
refused, which is the same answer from the outside.

That firewall also has **no rule for port 22**. Public SSH to either server is
blocked; Tailscale is the only way in, and the Cloud Console is the only
fallback if the tailnet breaks. This is the concrete form of the out-of-band
argument for putting state here rather than on samson or plop.

Two things follow:

- **It is a single layer.** Detach the firewall, delete it, or add one
  over-broad rule and postgres is public instantly. Narrowing the docker
  binding turns one protection into two independent ones. Worth doing.
- **`ufw` is not a substitute.** Docker writes its own nat and `DOCKER-USER`
  rules and publishes straight past it. The narrowing has to happen in the
  compose `ports:` line.

The binding should be narrowed to `127.0.0.1` plus bumba's tailnet address.
Before doing that, check `pg_stat_activity` for client addresses — containers
on `db-network` reach it as `db:5432` and are unaffected, but anything
connecting over the public IP would be cut off. That edit auto-deploys via
portainer, which is harmless for a port binding (no manual prerequisite, unlike
the change that cost five weeks of backups) but verify promptly rather than
assuming.

### The one credential tofu must never manage

`tofu_state`'s password is created by hand, above, and stays that way.

The workload layer manages postgres roles. If it also managed *this* role with
a `random_password`, the credential for reading state would be stored inside
the state it unlocks — and the day it is not in the environment, there is no
way to read state to find out what it is. Recovery means going in as superuser
and `ALTER ROLE`, so it is not permanent, but routine rotation would brick the
tooling at the worst moment.

Encryption does not help here, which is worth being precise about: the
passphrase decrypts the row *once the row has been fetched*, and fetching it is
the part that needs the database credential. Two secrets, two jobs.

In a file full of `postgresql_role` blocks this one looks like all the others.
That is exactly why it is written down here.

### State history

The pg backend stores one row per workspace and overwrites it. No history —
and the failure that matters is not "state was lost" but **"state is wrong"**:
a half-failed apply, a `tofu state rm` on the wrong address, an `import` with a
wrong id binding a resource to the wrong live object. Every one of those wants *yesterday's state*.

Add it: `./bootstrap-state-history.sh`, after the first `tofu init`. It creates
a `states_history` table and an `AFTER UPDATE OR DELETE` trigger, so it does
not depend on how the backend chooses to write, and it is idempotent.

That gives per-apply granularity — finer than S3 object versioning — queryable
by timestamp, and it rides along in the `pg_dump` to samson that already runs.
At roughly 50 KB a row it can go unpruned for years. The script prints the
inspect and roll-back queries when it finishes.

### A sharp edge worth knowing

State encryption and `tofu state push` do not get along.

If an apply fails *after* doing its work but *before* persisting state,
OpenTofu drops an `errored.tfstate` and tells you to recover with
`tofu state push errored.tfstate`. That file is encrypted, and the push
refuses to read it:

```
Error: Failed to read source state "errored.tfstate"
Unsupported state file format: This state file is encrypted and can not be
read without an encryption configuration
```

This happened on 2026-09-16, caused by the first version of
`bootstrap-state-history.sh` (see the comment at the top of that script).

It did not matter that time, because the failed apply had only **imported**
things — nothing was created, the backend still held the pre-apply state, and
re-running `tofu apply` simply redid the idempotent work. Check the plan first:
if it still shows the same pending actions, the backend is untouched and a
rerun is safe.

It would matter if the failed apply had **created** something, because those
resource IDs would exist only in the encrypted file and only in the live
infrastructure. The recovery then is to identify what was created and `import`
it, rather than to push. Worth knowing before you need it — and one more reason
that a change to the state plumbing is not a casual change.

### Locking

Advisory locks, which is genuine database locking rather than a conditional-write
trick that depends on an object store having implemented `If-None-Match`
correctly. This is the one axis where `pg` beats every other option outright.

## Prerequisites

```bash
# Arch/omarchy. psql, ssh and tailscale are already present; these two are not,
# as of 2026-09-16.
sudo pacman -S opentofu hcloud

# Everything at once. Each value is taken from the environment if already set,
# and prompted for otherwise -- no secret manager required, and no secret
# stored in the file.
. ./env.sh

# The Hetzner ids in imports.tf are filled in (2026-09-16). These re-verify
# them, and `discover.sh` does the same for postgres:
hcloud server list -o columns=id,name,type,location,status   # `type`, not `server_type`
hcloud storage-box list
hcloud firewall list
hcloud volume list

# Read this before trusting any plan. Retired types are not flagged -- they are
# simply ABSENT, or listed only in locations you are not in. That is how bumba's
# cpx11 reads: present, but `ash, hil` only.
hcloud server-type list
```

`extra/hcloud` is 1.67.0 and `extra/opentofu` is 1.12.1 on omarchy. The Cloud
Console shows the same ids if you would rather not install the CLI.

## Workflow

This is the sequence that was followed on 2026-09-16, kept because the second
pass (`imports.tf`) repeats it.

**1. Set up state and the environment** — see "One-time setup" above.

**2. Let the provider write the resource bodies.**

```bash
tofu init
tofu plan -generate-config-out=generated.tf
```

Forty-odd attributes read from the live API, rather than transcribed by hand
from the console. `generated.tf` is gitignored — it is scratch.

**3. Move the generated blocks** into `servers.tf`, `volumes.tf` and
`storage-box.tf`, then delete `generated.tf`.

**4. Add the lifecycle guards** (below) to every adopted resource.

**5. `tofu plan` — and read it.** "No changes" means done. Anything else means
step 3 or 4 is wrong. Do not apply your way out of a diff at this stage.

Only once that is clean should the token be swapped for a read/write one.

## The lifecycle guards

Add these by hand after step 3. `-generate-config-out` does not write them,
and they are the entire safety mechanism.

### Servers

```hcl
resource "hcloud_server" "bumba" {
  # cpx11 -- NOT orderable in fsn1 as of 2026-09-16. A destroy here is
  # one-way: the create half fails and Zitadel, the database and this
  # state file do not come back.
  # ... generated attributes ...

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      image, # the creating image may no longer exist
      ssh_keys, # forces replacement in the hcloud provider
      user_data, # same
    ]
  }
}
```

Attributes that force replacement are roughly `image`, `location`/`datacenter`,
`ssh_keys` and `user_data`. `server_type` can usually be increased in place to
an *available* type; what you cannot do is go back to a deprecated one.

### Volume

```hcl
resource "hcloud_volume" "bumba_db" {
  # ... generated attributes ...

  lifecycle {
    prevent_destroy = true
  }
}
```

Volumes resize online and never shrink. When 100 GB stops fitting the
migration (~118 GB of data against 94 GB free), raising `size` here and running
`resize2fs` on bumba is an in-place change — not a replacement.

### Firewall

```hcl
resource "hcloud_firewall" "default" {
  # ... generated attributes ...

  lifecycle {
    prevent_destroy = true
  }
}
```

Not a formality. `firewall-1` is the only thing standing between the internet
and bumba's `0.0.0.0:5432` postgres — the one now holding this state. Rule
changes are in-place and reversible; destroying the resource exposes the
database the same second.

### Storage Box

```hcl
resource "hcloud_storage_box" "backups" {
  # ... generated attributes ...

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      ssh_keys, # the API cannot update these -- a change forces REPLACEMENT
      password, # rotate in the console, not here
    ]
  }
}
```

`ssh_keys` is the dangerous one, and it is not a theoretical risk: provider **v1.58.0 changed it from ignored to
replacement-forcing**. The Hetzner API has
no update path for those keys, so the provider's only way to reconcile a
difference is to destroy and recreate — which would take the off-site kopia
repository with it. `prevent_destroy` turns that into a refused apply;
`ignore_changes` stops it being proposed at all.

Storage Box support stopped being experimental in v1.60.0, which is why the
`~> 1.69` pin in `providers.tf` is a floor worth keeping rather than a
formality.

### Databases

```hcl
resource "postgresql_database" "zitadel" {
  # ...
  lifecycle {
    prevent_destroy = true
  }
}
```

### Roles — not adopted yet, and why

A role's password cannot be read back: postgres stores only a SCRAM hash. An
imported `postgresql_role` therefore lands in state with `password = ""`, and
the next plan will cheerfully propose setting the **live** password to empty —
an outage for whatever uses it.

```hcl
resource "postgresql_role" "score_api" {
  name  = "score_api"
  login = true
  # no `password` at all

  lifecycle {
    ignore_changes = [password]
  }
}
```

**No password is supplied, and `env.sh` does not prompt for one.** That is a
real difference from `hcloud_storage_box`, not an oversight: there `password`
is a **required** attribute, so tofu refuses to plan without a value.
`postgresql_role.password` is **optional**, so it can simply be absent — and
with `ignore_changes` set, a value would never be used anyway. Carrying nine
role passwords through the environment to feed attributes tofu has been told
to ignore would be secret sprawl for nothing.

So at adoption, tofu describes what a role *is* — login, createdb, connection
limit, memberships — and explicitly not what its secret is. The password stays
where it lives today, in the application's own config.

### Where roles should end up

That is the adoption state, not the destination. The design in
[`../docs/iac-migration.md`](../docs/iac-migration.md) has tofu **generating**
these:

```
random_password -> postgresql_role.password
                -> templatefile -> docker_secret -> the service
```

which is what removes the placeholder-secrets-in-git pattern entirely. Getting
there means dropping `ignore_changes` for that role and letting tofu set the
password — but the password change and the application's config have to move in
the same step, or the app is left holding the old one. So it is a per-app
cutover, deliberately, one at a time. Not something to do while adopting.


## What is verified and what is not

| resource                     | id          | source                                |
|------------------------------|-------------|---------------------------------------|
| `hcloud_server.mindy`        | `124902827` | metadata service on mindy, 2026-09-15 |
| `hcloud_server.bumba`        | `100750341` | `firewall-1` "Applied To", 2026-09-16 |
| `hcloud_volume.bumba_db`     | `103225027` | `/mnt/HC_Volume_103225027` mountpoint |
| `hcloud_storage_box.backups` | `625908`    | `hcloud storage-box list`, 2026-09-16 |
| `hcloud_firewall.default`    | `10051212`  | `hcloud firewall list`, 2026-09-16    |

All four first-pass ids are filled in. Nothing is left to guess before the
first plan.

### Server types, 2026-09-16 — this is the whole reason for the layer

| server | type    | cores / RAM / disk | orderable in `fsn1`?        |
|--------|---------|--------------------|-----------------------------|
| mindy  | `cx43`  | 8 / 16 GB / 160 GB | **yes** — current catalogue |
| bumba  | `cpx11` | 2 / 2 GB / 40 GB   | **NO** — `ash, hil` only    |

`hcloud server-type list` no longer shows `cx11`–`cx51` at all, and the entire
`cpx*1` line is US-only. The European generations are `cpx*2`, `cx*3`, `cax*`
and `ccx*`.

So bumba is not a hypothetical. It runs Zitadel, the database, and this state,
on a type that cannot be created in its own location. A replacement plan
destroys successfully and then fails to create. `prevent_destroy` is the
mechanism that makes that plan impossible to run rather than merely unwise.

The escape hatch exists and is worth taking deliberately rather than
discovering under pressure: `server_type` rescales **in place** to an available
type, and from `cpx11` the natural steps are `cpx22` (2 / 4 GB / 80 GB) or
`cpx32` (4 / 8 GB / 160 GB). A rescale that grows the disk is irreversible and
needs a reboot, so it is a planned change — but it is an in-place change, not a
replacement, and it moves bumba back onto a line Hetzner still sells.

Also confirmed on mindy, 2026-09-15: `fsn1-dc8`, region `eu-central`, public
IPv4 `91.99.120.54`, IPv6 `2a01:4f8:c012:a6f3::1/64`, Debian 13 (trixie),
152.6 GiB root disk, no attached volume.

bumba could not be reached from omarchy — Tailscale SSH sits in ACL **check**
mode and blocks on browser authentication, exactly as noted in
[`samson/backup/README.md`](../samson/backup/README.md). Setting that rule to
`accept` for own-devices is a prerequisite for unattended runs of this layer
anyway.

## What the adoption turned up

The config matches reality exactly, because that is the only way `tofu plan`
can report "No changes". Everything below is a difference between what the
infrastructure **is** and what it arguably **should be** — each one a
deliberate change to make afterwards, on purpose, reading the diff. None of
them are silently fixed in the `.tf` files.

| finding | state |
|---|---|
| **bumba has no backups** (`backups = false`) while **mindy does** (`true`, window 18-22) | Inverted. mindy runs replaceable apps; bumba runs Zitadel, the database, and this layer's own state — on a server type `fsn1` will not sell again. Hetzner backups cost 20% of the server price, so roughly €1/month for a cpx11. |
| **`delete_protection = false` on both servers** | The volume already has it `true`. `prevent_destroy` only stops *tofu*; the Console and a raw API call are unaffected. Worth enabling on bumba at minimum. |
| **`delete_protection = false` on the Storage Box** | It is one of the three copies of the family photos. |
| **Storage Box `reachable_externally = false`** | Fine today, because kopia runs on mindy inside Hetzner. It **blocks the planned reverse flow** in [`docs/data-architecture.md`](../docs/data-architecture.md), where samson pushes ~810 GB of curated media from home. That flag has to change before that flow can exist. |
| **bumba is `debian-12`**, mindy is `debian-13` | A major version behind. Debian 12 is supported to 2028, so not urgent — but it is the box carrying auth and the database. |
| `rebuild_protection = false` on both servers | Lower stakes than delete protection, same idea. |

Two of these — bumba's missing backups and the `cpx11` rescale — point the same
way, and the rescale window is the natural moment to fix both.

## What discovery turned up, 2026-09-16

bumba runs PostgreSQL 17.10 (alpine), `max_connections = 100`, data in
`/data/postgres` — which is the volume, through
`/docker-volumes/db/data -> /mnt/HC_Volume_103225027/db/data/`.

Five databases and nine roles. Three things are worth resolving before they
become tofu resources.

### Roles cannot be adopted naively

postgres stores only a SCRAM hash, so a role's password cannot be read back.
An imported `postgresql_role` therefore lands in state with `password = ""`,
and the next plan will cheerfully propose setting the **live** password to
empty — an outage for whatever uses it.

Every adopted role needs `ignore_changes = [password]`, without exception.
This is the same trap `hcloud_storage_box` sets in the infra layer, and the
reason the first pass adopts databases only.

### Three `databasus-*` roles of unknown provenance

```
databasus-017701f4
databasus-41ec78f0
databasus-992bb9b2
```

Login roles owning no database, auto-named with a hex suffix.
`databasus-41ec78f0` is the one the memos dump referenced during the
2026-09-15 migration.

If `databasus` provisions these, adopting them puts two systems in charge of
the same objects — the portainer problem in a different costume, and the
failure mode is the same: they reconcile against each other, quietly, until
something breaks. Find out what creates them before importing.

### `zitadel_root` is a superuser

`rolsuper = t`. Zitadel needs elevated rights to create its schema at first
boot; it does not need superuser permanently. Worth checking against Zitadel's
own documented requirements rather than encoding the status quo as intentional
— importing it as-is makes "Zitadel's database role is a superuser" a
version-controlled decision.

### Also noted

`memos` (112 MB) is the orphan left behind by the migration to mindy. It
should be **dropped**, not adopted, once the notes are confirmed visible in
the UI. Adopting it would mean importing a mistake and then removing it from
state again.

Only `plpgsql` is installed anywhere, so no extension resources are needed
yet. That changes with immich, which needs pgvector.

## Adopting Zitadel

Not wired in yet, deliberately. A configured provider authenticates on **every**
`tofu plan`, so adding the block before the credential exists would break a
config that currently plans clean. Credential first, wiring second.

What is running: Zitadel v4.17.3 at `auth.wvl.app`, first-instance org
`Zitadel`, database `zitadel` owned by `zitadel_root`, application user
`zitadel_user`. Config in
[`../home-eu-central-1/zitadel/`](../home-eu-central-1/zitadel/).

### Step 1 — a machine user for terraform, by hand

This is the one part that cannot be automated: the provider needs credentials
issued by the instance it is about to manage.

In the Zitadel console:

1. **Users → Service Users → New.** Username `terraform`, access token type
   **Bearer**.
2. Grant it **IAM_OWNER** at the instance level (Instance → Administrators),
   or **ORG_OWNER** if it should only ever touch one org. IAM_OWNER is what
   lets `discover-zitadel.sh` enumerate every org.
3. **Personal Access Tokens → New.** Copy it once — it is not shown again.

**Do not reuse `/docker-volumes/zitadel/login-client/login-client.pat`.** That
belongs to the login UI, is scoped `IAM_LOGIN_CLIENT`, and coupling terraform
to it means rotating either one breaks the other.

Keep the token out of this repo — it is public. `~/.config/zitadel/terraform.pat`
with mode `600` is fine.

### Step 2 — discovery

```bash
ZITADEL_PAT="$(cat ~/.config/zitadel/terraform.pat)" ./discover-zitadel.sh
```

Plain HTTP against the Zitadel APIs: no provider, no state, no tofu. It prints
the token's identity, then every org, project, application and action with its
id.

Note that zitadel import ids are frequently **composite** — an application is
`<org_id>_<project_id>_<app_id>` rather than a bare id — and the shape differs
per resource type. Check the provider docs per resource instead of assuming.

### Step 3 — wiring

Once discovery returns something, `modules/zitadel/` gets a provider block, the
root gets a `zitadel` entry in `required_providers` and a module call, and the
import blocks go in `imports.tf` like everything else. The auth attribute to
use (`token` vs `jwt_profile_file`) is worth confirming against
`tofu providers schema -json` after the first `init` rather than taking on
trust.

### Why this is the piece worth having

Thirteen `wvl.app` hostnames are served by applications whose OIDC clients were
clicked into a web console by hand, with the client id then pasted into a
config file. That is the chain
[`../docs/iac-migration.md`](../docs/iac-migration.md) is built around:

```
zitadel_application_oidc -> client_id ─┐
postgresql_role          -> password ──┴─> templatefile -> docker_secret -> service
```

Compose cannot express any of it. This is where the workload layer stops being
bookkeeping and starts doing something compose could not.

### One thing to fix while here

[`../home-eu-central-1/zitadel/zitadel-initial-steps.yaml`](../home-eu-central-1/zitadel/zitadel-initial-steps.yaml)
contains `Password: Password1234!` in a public repo. Blast radius is small —
bootstrap-only, and `PasswordChangeRequired: true` — but confirm that account's
password was actually changed rather than assuming the flag did it.

## Deliberately not here yet

- **Containers.** `docker_service` / `docker_secret` need swarm mode; the hosts
  run plain docker with portainer today. That is open question 2 in
  [`../docs/iac-migration.md`](../docs/iac-migration.md), and it is not
  blocking database adoption.
- **Zitadel.** The provider needs a service-account key that Zitadel writes at
  first boot. Yours is already running, so this is a one-time manual key
  generation plus `jwt_profile_file` — not a stage boundary, but not this pass.
- **The portainer cut.** Once tofu owns a service, portainer's daily git
  redeploy of the same stack must stop, or they reconcile against each other.
  Migrate one host fully, delete its stacks, then move on. Databases are safe
  from this because portainer does not manage them.
