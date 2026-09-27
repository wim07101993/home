# backrest

restic with a web UI, replacing kopia. One instance per host: mindy and samson.

## Why this replaced kopia

kopia stores its policies **and its source list inside the encrypted
repository**. Making that declarative needs a reconcile loop in each direction:
`policy import --delete-other-policies` for policies, and a prune pass for
sources. The second never existed, so adding a path created a source and
removing one left it in the repository forever, still on the global schedule.

That is not theoretical. `/data/media` survived its own removal from the config
on 2026-09-25, inherited the global schedule, and was one scheduled run from
writing 8.4 TB into 4.5 TB of free space. Caught by hand, twice.

Backrest keeps configuration in **one JSON file** and history in SQLite. A path
removed from `var.paths` is simply absent from the next snapshot, and older
snapshots age out under `var.retention`. Nothing is reconciled, and no history
is deleted to express "stop backing this up".

| | remove a path from config |
|---|---|
| kopia | source persists, still scheduled → needs prune → **deletes history** |
| restic | not in the next snapshot; old ones age out on retention |

### The ledger

Deleted: `policies.json` (1061 lines), `bootstrap-sources.sh` (100),
`heartbeat.sh` (79), `prune_sources`, `KOPIA_IDENTITY`, `import_policies`, the
self-signed TLS pair, and the `server users add || set` entrypoint dance.

Added: `start.sh`, two lines.

Gained: scheduled `restic check`. kopia never verified here, so "the backups
exist" and "the backups are readable" were the same assumption for years.

## How it is wired

```
config.json   rendered by main.tf, uploaded INTO THE CONTAINER LAYER
              (not bind-mounted -- a UI edit cannot outlive the next apply)
/data         SQLite operation log: runs, progress, sizes, stderr. Derived.
/cache        restic's cache. Rebuildable.
/backup/<k>   the sources, read-only, one bind per var.mounts entry
```

Two host directories must exist before the first apply, because a bind mount's
source is never created by docker:

```
<config_path>/data
<config_path>/cache
```

## Why rclone is in the path

restic's SFTP backend **cannot use a password** -- it shells out to `ssh` and
offers no way to supply one ([restic#448]). Key auth is the alternative and is
not available here: Storage Box SSH keys are a box-level attribute that
`modules/hetzner` keeps in `ignore_changes` because setting it forces
replacement of the box holding every backup, and
`hcloud_storage_box_subaccount` has no `ssh_keys` attribute at all (verified
against the provider schema, 2026-09-26).

So restic reaches the box through rclone, which does support password auth and
ships in the image. rclone stores passwords **obscured** and tofu cannot compute
that, which is the entire reason `start.sh` exists. Everything else about the
remote is declared in the container's `env`, where it shows up in a diff.

[restic#448]: https://github.com/restic/restic/issues/448

## Traps

- **The image tag needs the `v`.** `1.14.1` does not exist. The bare tag is the
  **alpine** build, which is load-bearing: `-scratch` has no rclone, no curl and
  no `sh`, and would fail at runtime rather than at plan time.
- **`config_version` is coupled to `image_tag`.** Backrest computes its current
  version as the *length of its migration list*. Too low and it migrates the
  file out from under this module; too high and it refuses to start; `0` is
  rejected outright for a non-empty config.
- **`passwordBcrypt` is base64(bcrypt)**, not a bare hash -- a bare hash fails
  every login while looking exactly like a wrong password.
- **Use `random_password.bcrypt_hash`, never tofu's `bcrypt()`.** The function
  re-salts on every evaluation, so the rendered file would differ every plan and
  replace the container on every apply.
- **`guid` and `autoInitialize` are mutually exclusive.** Setting both fails
  validation.
- **Unknown JSON fields are silently discarded** (`DiscardUnknown: true`), so a
  misspelled key does nothing rather than erroring. Same shape as kopia's empty
  policies: it looks configured and is not.
- **`hostname` is load-bearing.** restic tags snapshots with the host, so
  without it the container ID becomes the identity and history restarts on every
  recreate. Reproduced in the preflight: a snapshot landed under
  `6e53772625d4`.
- **The repository password carries `prevent_destroy`, and must.** It is
  generated (`random_password.backrest_repository` in the root) and has no reset
  path. A `-replace`, or any `keepers` change, regenerates it; the next apply
  writes a new `config.json` and restic can no longer open either repository,
  with the old value gone from state. Keep a vault copy --
  `tofu output -raw backrest_repository_password`.
- **Never `replace(p, "/data/", "/backup/")`.** OpenTofu treats a slash-wrapped
  substring as a **regex**, so that pattern is `data` and the result is
  `//backup//media/...`. See `samson-media-sources.txt`.

## Observability

The UI answers "what happened" when someone looks. gatus answers "is anyone
looking" -- see `var.gatus_endpoint`. Both are needed: kopia's two outages (five
weeks crash-looping, four days cleanly stopped) were invisible precisely because
nothing pushed.

A **skipped** run pushes success. `skipIfUnchanged` means a week of untouched
documents produces no snapshot, and treating that as failure would page about a
repository that is entirely up to date.

## Verified before first apply (2026-09-26)

Rendered `config.json` was fed to `garethgeorge/backrest:v1.14.1`:

- config validated -- version 6, enum names, bcrypt, `autoInitialize` with no guid
- `commandPrefix` applied: `/bin/nice -n 10 ionice -c 3 /bin/restic ...`
- restic 0.19.1 bundled at `/bin/restic`
- against a local SFTP server: `rclone obscure` → password auth → `restic init`
  → backup of `The Lion King (1994)` (spaces and parentheses) → snapshot listed
- host key pinning accepts the correct key and **refuses** a wrong one

## Cutover

Runs in parallel with kopia. The repo formats are unrelated, so this is a fresh
upload, not a conversion -- and a backup migration is not the place to trust a
new tool before it has read back what it wrote.

kopia comes out once both instances hold a full retention window **and one
restore has actually been tested from the UI**.
