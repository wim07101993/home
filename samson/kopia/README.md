# Kopia migration: mindy → samson

Moving the *snapshot* work to samson while the *repository* stays on mindy.

## Why

Kopia ran on mindy and read samson's data back over NFS-over-Tailscale. Every
run walked the entire tree across the home uplink to decide what had changed,
which is what produced the recurring stalls in mindy's `dmesg`:

```
nfs: server 100.71.248.106 not responding, still trying
```

clustered at 00:05 / 02:05 / 03:05 / 05:05. Those stalls are also what took
filebrowser down on 2026-08-09 — it blocked in `stat()` on a hung `hard` mount
before it ever opened its HTTP listener.

## What does not change

The Hetzner Storage Box stays reachable from **inside Hetzner only**. Its
credentials live on mindy and nowhere else. Samson connects to mindy's kopia
repository server with a per-machine username/password and, per the Kopia docs,
clients "require no knowledge of repository storage credentials."

The UI stays on mindy. Same repository, so samson's snapshots appear there.

## Target shape

```
before:  samson (data) ──NFS over WAN──→ mindy [kopia] ──→ Storage Box
after:   samson [kopia client] ──content over Tailscale──→ mindy [kopia server] ──→ Storage Box
                    │
                    └── scans local disk
```

---

## Phase 0 — pre-checks

On **samson**, confirm the exports are real local paths (OMV bind-mounts them,
but verify rather than assume — the compose mounts `/export` read-only):

```bash
ls -la /export/
findmnt /export/wim
```

On **mindy**, confirm the current exposure before changing it:

```bash
ss -lntp | grep 51515
curl -s -o /dev/null -w '%{http_code}\n' http://91.99.120.54:51515/
```

If that curl answers, the repository API is currently on the public internet
over cleartext HTTP. Phase 1 closes it.

## Phase 1 — TLS + Tailscale-only bind on mindy

Generate the certificate once (the permanent entrypoint only references it):

```bash
cd /path/to/mindy/kopia
docker compose down
docker compose run --rm --entrypoint sh kopia -c '
  export KOPIA_PASSWORD="$(cat /run/secrets/repository_password | tr -d "\r\n")"
  kopia server start --tls-generate-cert \
    --tls-cert-file=/app/config/kopia.cert \
    --tls-key-file=/app/config/kopia.key \
    --address=127.0.0.1:51515 --config-file=/app/config/repository.config'
```

It prints `SERVER CERT SHA256: ...` then keeps running — copy the fingerprint
and Ctrl-C. Now bring up the new compose and record the fingerprint:

```bash
docker compose up -d
docker exec kopia openssl x509 -in /app/config/kopia.cert -noout \
  -fingerprint -sha256 | sed 's/://g' | cut -f 2 -d =
```

Put that value in `samson/kopia/.env` as `KOPIA_SERVER_CERT_FINGERPRINT`.

> The UI is now **https://100.127.106.121:51515** with a self-signed cert, so
> expect a browser warning, and it is only reachable over Tailscale. Update
> `mindy/homepage` if it links to the old `http://` address.

Verify the public port is gone:

```bash
curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://91.99.120.54:51515/   # should fail
```

## Phase 2 — create samson's server user

Users are `username@hostname`, lowercase, and must match what the client
overrides itself to (`wim@samson`):

```bash
docker exec -it kopia sh -c '
  export KOPIA_PASSWORD="$(cat /run/secrets/repository_password | tr -d "\r\n")"
  kopia server user add wim@samson --config-file=/app/config/repository.config'
```

It prompts for a password — this is a **new** password, unrelated to the
repository password. Then restart so the server picks up the user list:

```bash
docker compose restart kopia
```

Kopia's built-in ACLs already let a user reach their own snapshots, so
`kopia server acl enable` is not needed unless you want custom rules.

## Phase 3 — deploy the client on samson

```bash
mkdir -p /docker-volumes/kopia/{config,cache,logs}
printf '%s' 'THE-PASSWORD-FROM-PHASE-2' > /docker-volumes/kopia/server_user_password.txt
chmod 600 /docker-volumes/kopia/server_user_password.txt

cd /path/to/samson/kopia
docker compose up -d
docker compose logs -f kopia-client
```

**The check that matters.** Kopia is content-addressed and deduplicates across
the whole repository, so the first samson snapshot should *hash* everything but
*upload* almost nothing — the content is already there from mindy's runs. The
log line reports both:

```
Snapshotted 1 directory, N files, X GB (hashed ...), 0 B uploaded
```

A large uploaded figure means dedup did not match — stop and investigate before
phase 4 rather than paying for a second full copy.

Then confirm the snapshots landed under the new identity:

```bash
docker exec kopia sh -c 'export KOPIA_PASSWORD="$(cat /run/secrets/repository_password|tr -d "\r\n")"; \
  kopia snapshot list --all --config-file=/app/config/repository.config' | grep samson
```

## Phase 4 — cut over

Only once samson has produced at least two good snapshot cycles.

1. In `mindy/kopia/docker-compose.yml`, delete the `/docker-volumes/kopia/data:/data:ro`
   line (marked `PHASE 4`), then `docker compose up -d`.
2. Remove the nine `/docker-volumes/kopia/data/*` entries from `/etc/fstab` on
   mindy (see `mindy/fstab`), then:
   ```bash
   umount /docker-volumes/kopia/data/*
   systemctl daemon-reload
   ```
3. Leave the old `wim@<mindy>` snapshots alone. They are still valid restore
   points and cost almost nothing (shared content). Let retention age them out,
   or once samson has enough history:
   ```bash
   kopia snapshot delete --all-snapshots-for-source wim@mindy:/data/wim --delete
   ```

## Rollback

Nothing here is destructive until phase 4 step 2. To back out: stop
`kopia-client` on samson, re-add the `/data` mount on mindy, restart. The
repository itself is untouched by any of this.

## Known trade-offs

- **Snapshot identity changes** from `wim@mindy:/data/*` to `wim@samson:/data/*`.
  Kopia treats those as separate sources, so policies (retention, compression,
  exclusions) do **not** carry over — set them on the new sources, either in
  mindy's UI or with `kopia policy set`.
- **Scheduling is a loop, not kopia's scheduler.** The entrypoint runs
  `snapshot create` every `SNAPSHOT_INTERVAL_SECONDS` (default 6h). Simple and
  easy to reason about, but it does not catch up on missed windows after
  downtime. If you would rather have kopia's own scheduler and a status UI on
  samson, run `kopia server start` there instead — it costs a second TLS cert
  and a second UI password.
- **Backups now depend on samson being up** rather than on mindy being up. Given
  the data also lives on samson, that is the correct coupling.
