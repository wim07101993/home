# Local backup: samson array → 14 TB USB drive

Full local replica of the btrfs array using `btrbk` (btrfs send/receive).
Config: [`btrbk.conf`](./btrbk.conf).

Context: [`../incidents/2026-08-06-array-overheating.md`](../incidents/2026-08-06-array-overheating.md)

## Why this exists

Until now `media` (~8.3 TB) existed in **exactly one place** — a btrfs RAID10
whose `devid 1` is at 2,016 pending sectors and climbing. Everything else is
covered by kopia to the Hetzner Storage Box and was verified restorable on
2026-09-09.

This drive removes that single point of failure, and in doing so unblocks two
decisions:

- **no €450 replacement drive.** Once media has a second copy, losing the array
  costs a restore, not data.
- **`WSD320VH` can be dropped without replacement**, once media is protected.

Note the profile choice this drives: convert the remaining three drives to
**`raid1`, not `single`**. This drive is refreshed only twice a year, so a
`single`-profile array losing a disk would mean fetching the backup from
off-site, a 13-16 hour restore, and losing up to six months of additions. raid1
across 3 x 7.28 TiB gives 10.9 TiB usable against 8.39 TiB in use -- it survives
a drive failure outright, at the cost of ~2.5 TiB of growth headroom. With three
7.27-year-old drives that ran five months at 94 C, that trade is worth making.

## Division of labour

| | this drive | Hetzner Storage Box |
|---|---|---|
| tool | `btrbk` (btrfs send/receive) | `kopia` |
| covers | everything, 8.39 TiB | ~119 GB + ~810 GB curated media |
| encrypted | no | yes |
| restore needs | nothing — mount and copy | kopia + repository password |
| protects against | array loss, accidental deletion | fire, theft, site loss |

## The hardware

```
Bus 004 (xhci)  Port 004 → sdf   5000M   14 TB Seagate Expansion  00000000NT17ADLS
Bus 002 (ehci)  Port 005 → sdg    480M   4.5 TB  (ext4, corrupt journal)
Bus 002 (ehci)  Port 006 → sdh    480M   4.5 TB  (Synology .hbk archives, 509 GB)
```

`sdf` is the only drive on a USB 3.0 port — keep it there. The other two run at
USB 2.0 (~35-40 MB/s real); Bus 004 has free ports if either is ever used for
rotation.

**What was destroyed:** `sdf` previously held `syno_full_backup.hbk`, a 10 TB
Synology HyperBackup archive dated 2026-01-24. Deliberately discarded — it is
the archive that already proved partly unreadable in February 2026, the current
array was restored *from* it (so it holds nothing unique), and extracting it
needs Synology tooling that no longer exists here. A backup that cannot be
restored is not a backup.

`sdh` is untouched. Its three `.hbk` archives are the only pre-March copy of
homes/familie/audio, they cost only 509 GB of 4.6 TB, and there is no reason to
reclaim the space.

---

## Setup

### 0. Pre-flight — SMART is not available on this drive

**Confirmed unavailable.** The Seagate Expansion HDD bridge (`0bc2:2038`) does
not implement ATA passthrough under any device type:

```
sat / sat,12 / sat,16 / auto   unsupported field in scsi command
usbsunplus / usbprolific       unsupported scsi opcode
usbjmicron / usbcypress        no device connected / unknown error
scsi                           Product: Expansion HDD   <- identity only
-T permissive                  Device Model: [No Information Found]
```

There is no reallocated-sector count, no temperature, no self-test for this
drive. `usb-storage.quirks=0bc2:2038:u` addresses UAS bugs rather than
passthrough and is unlikely to change this.

**Compensate with btrfs instead**, and treat it as the better instrument rather
than a consolation. A scrub reads every block and verifies every checksum — it
proves the data reads back correctly, where SMART only reports what a drive
believes about itself. The 2026-08 incident began with SMART attributes that
were completely accurate and that nothing was reading.

Concretely:

- **scrub immediately after the first full copy**, not a month later — it is the
  only way to confirm 8.4 TB landed intact (step 6)
- **scrub monthly thereafter**, and monitor the result
- **treat this drive as one layer of three** (array, this drive, Storage Box),
  never as a single point of trust

If SMART on the backup ever becomes important, shucking the drive onto one of
the four free ports on the 9211-8i restores it fully — at the cost of the
detachability that makes a USB backup drive useful.

### Encryption: deliberately not used

The drive is unencrypted by decision, not oversight. It travels and is stored
off-site, so a lost or stolen drive exposes the full photo and document archive
in the clear — accepted in exchange for a backup that any Linux machine can
mount and read with no passphrase and no tooling, which is worth a lot in the
situation where this drive is actually needed.

The kopia copy on the Storage Box remains encrypted, so the off-site data is not
unprotected everywhere — only on this drive.

If this is ever revisited, LUKS has to go *underneath* the filesystem, so it
means reformatting and a full 8.4 TB re-send.

### 1. Format

**Destroys everything on `sdf1`.**

```bash
umount /dev/sdf1 2>/dev/null
mkfs.btrfs -L backup-14t -m dup -d single -f /dev/sdf1
blkid /dev/sdf1
```

`-m dup` keeps two copies of metadata on the single disk, so one bad sector
cannot take the filesystem tree with it. `-d single` because the data is a
replica — redundancy belongs on the source, not here.

### 2. Mount

`noauto`: the drive is meant to be detachable, and a missing USB device must
never delay boot.

```bash
mkdir -p /mnt/backup-14t
echo "UUID=$(blkid -s UUID -o value /dev/sdf1)  /mnt/backup-14t  btrfs  noauto,noatime,nofail  0 0" >> /etc/fstab
systemctl daemon-reload
mount /mnt/backup-14t
findmnt /mnt/backup-14t
```

### 3. Install and configure btrbk

```bash
apt install btrbk mbuffer
cp btrbk.conf /etc/btrbk/btrbk.conf
```

Three things the package does not do for you:

**1. Disable the timer Debian enables.** btrbk's postinst runs:

```
Created symlink '/etc/systemd/system/timers.target.wants/btrbk.timer' -> ...
```

That fires `btrbk run` **daily**. With this drive absent ~94% of the time, each
run creates a source snapshot, fails to send it, and leaves it on the array.
Against `snapshot_preserve_min 18m` that accumulates roughly 550 undeletable
snapshots before the first expires. Runs here are manual by design:

```bash
systemctl disable --now btrbk.timer
```

**2. Install `mbuffer`.** It is only a *Recommends*, so it may not arrive with
btrbk, and without it `stream_buffer` is silently ignored:

```
WARNING: Found option "stream_buffer", but required executable "mbuffer" does not exist
```

It keeps the send pipe full when USB write throughput fluctuates, which it does.

**3. Create the snapshot directory.** btrbk will not create `snapshot_dir`
itself and aborts every subvolume without it:

```bash
mkdir -p /srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300/_btrbk_snap
```

Then:

```bash
btrbk -c /etc/btrbk/btrbk.conf dryrun
```

`dryrun` prints exactly what would be snapshotted and sent, and writes nothing.
Read it before proceeding — it is what caught all three of the above.

### 4. First run — small subvolumes first

~119 GB, finishes in minutes. Do this before the media run so a complete local
copy of everything irreplaceable exists as early as possible.

```bash
btrbk -v run photos audio audio-archive gezin-officieel \
              gezin-officieel-archive wim sara backups
btrfs subvolume list /mnt/backup-14t
```

### 5. Then media — overnight

~8.3 TB at 150-180 MB/s over USB 3.0 ≈ **13-16 hours**.

```bash
screen -S btrbk     # or tmux; do not run this on a connection that may drop
btrbk -v run media
```

Expect thousands of `critical medium error` / `read error corrected` lines from
`sdb` during this. That is **normal and harmless** — btrfs repairs each one from
its RAID10 mirror as it reads. Watch that the count of *uncorrected* errors
stays at zero:

```bash
btrfs device stats /srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300
journalctl -k -f | grep -E 'unable to fixup|csum failed'    # should stay silent
```

This full read is the best remaining use of `WSD320VH`.

### 6. Verify — before trusting any of it

> *"An untested backup is a hypothesis."*

```bash
SNAP=$(btrfs subvolume list /mnt/backup-14t | grep gezin-officieel | tail -1 | awk '{print $NF}')
diff -r /export/gezin-officieel "/mnt/backup-14t/$SNAP" && echo "IDENTICAL"
du -sh /export/gezin-officieel "/mnt/backup-14t/$SNAP"
```

Then restore one file to a scratch path and open it. Restoring 608 MB took two
minutes in August and changed the whole situation from frightening to annoying.

---

## Running it

**This drive lives off-site at family and is normally powered off.** It is
fetched roughly every **4 months**, stays here about a week, and goes back.

It is deliberately *not* carried on every visit. A drive that is here half the
time is a second local copy with extra steps — it shares every risk the array
has: fire, theft, a mistake with root, ransomware. The 4-month cycle keeps it
off-site **~94% of the time**, which is the property being bought.

**Keep it unmounted except while btrbk is actually running.** The week in the
house is unavoidable; a week *mounted* is not, and an attached filesystem is
reachable by anything that gets root on samson.

### Why staleness is acceptable here

| data | Storage Box | unique to this drive |
|---|---|---|
| photos, audio, gezin-officieel, wim, backups | yes, continuously | — |
| curated media (~810 GB) | yes | — |
| the rest of media (~7.5 TB) | **no** | **yes** |

The only data for which this drive is the sole second copy is uncurated films
and series — the slowest-changing category, and the one already classified as
replaceable. Everything with real consequences reaches Hetzner within hours.
This drive is the last resort, not the first line.

### The three copies

| copy | where | online | covers |
|---|---|---|---|
| array | samson, home | yes | everything (live) |
| kopia | Hetzner Storage Box | yes | ~119 GB + ~810 GB curated media |
| this drive | family, off-site | **no** | everything |

Three copies, two media types, one off-site, one air-gapped. Textbook 3-2-1.

### Procedure per visit

No systemd timer — a timer for a device that is absent 95% of the time only
generates failures. Run it by hand when the drive is attached:

```bash
mount /mnt/backup-14t                       # + cryptsetup open first, if LUKS
btrbk -c /etc/btrbk/btrbk.conf dryrun       # confirm it found a common parent
screen -S btrbk
btrbk -v run
btrfs subvolume list /mnt/backup-14t | tail
umount /mnt/backup-14t                      # + cryptsetup close, if LUKS
```

**Check the dry run each time**, and check for *two* different failures:

| dry run shows | meaning |
|---|---|
| `>>>` on every subvolume | correct — incremental |
| `***` (non-incremental) | the array pruned the common parent; this visit will take 13-16 hours instead of minutes. `snapshot_preserve_min` is shorter than your visit interval — raise it. |
| **only `+++`, no send lines** | **silent no-op.** btrbk only creates a target backup if retention would keep it; a bucket already filled means it transfers nothing and still reports success. |

The second one bit on 2026-09-14, on the most important run of all — the top-up
taken just before the drive went off-site. `btrbk -v dryrun` names it explicitly:

```
Checking for missing backups of subvolume ".../photos" in "/mnt/backup-14t/"
No missing backups found
```

Fixed by `target_preserve_min latest`, which guarantees the newest backup is
always preserved and therefore always created. **Verify the output, not the exit
status** — `finished success` is what a no-op looks like too.

### Scrub — when the drive is here, not on a schedule

A full scrub of 8.4 TB over USB 3.0 takes roughly as long as a full copy, so it
cannot happen every visit.

- **After the first full copy: mandatory.** It is the only way to confirm 8.4 TB
  landed intact on a drive with no SMART.
- **Afterwards: every visit is realistic.** Once the first full copy exists,
  each visit's incremental takes minutes, and the drive is in the house for a
  week — so an overnight scrub fits comfortably. Start it the evening the
  backup finishes and read the result the next day.

A powered-off drive in a cupboard is a low-bitrot environment — no heat, no
vibration, no spinning. Decay happens over years, not months, so infrequent
verification is a reasonable trade here in a way it would not be for a drive
running 24/7.

```bash
btrfs scrub start -B /mnt/backup-14t     # -B = foreground, reports at the end
btrfs scrub status /mnt/backup-14t
```

### Monitoring an infrequent backup

An Uptime Kuma push monitor still works — set the heartbeat interval to the
visit cadence **plus margin** (a 4-month cycle wants ~150 days, not 120, or it
alerts every time a trip slips by a fortnight). It then fires only when a backup
has genuinely been missed, rather than every day the drive is away:

```bash
btrbk -q run && curl -fsS -m 10 "https://status.wvl.app/api/push/<TOKEN>?status=up&msg=offsite-ok"
```

The thing being monitored is *"has too long passed since the last off-site
copy"*, which is the failure that actually happens with rotated drives — not a
disk fault, just months slipping by unnoticed.

## Stopgap: docker volumes on the 4.5 TB spare (`sdh`)

**2026-09-14.** Point-in-time, manual, unmonitored. Superseded by whatever the
rearchitecture provides — see [`../../docs/iac-migration.md`](../../docs/iac-migration.md).

Discovered while checking whether databasus was covered: **it was not, and
neither was anything else under `/docker-volumes/`.** btrbk sends only the
array's nine subvolumes; both hosts keep their container data on their root
disks, entirely outside every backup. The only prior copy was a manual
`cp backup-server/ .../backups/ -r` done by hand on 2026-08-01.

Written to `sdh` (ext4, Synology `.hbk` archives left in place) at
`/mnt/spare/docker-volumes-backup/2026-09-14/`:

| | size | contents |
|---|---|---|
| `samson-docker-volumes/` | 15 G | plex config 14 G, backup-server/databasus 1.3 G |
| `samson-named-volumes/` | 1.2 M | `portainer_data` — stack definitions, git URLs, stack env vars |
| `mindy/docker-volumes/` | 963 M | immich, db, kitchen-owl, filebrowser, traefik, homepage, memos configs + `_dumps/` |
| `mindy/named-volumes/` | 5.9 M | `portainer_data` |
| `plop/docker-volumes/` | 401 M | Home Assistant config 102 M, paperless 305 M |
| `plop/named-volumes/` | 94 M | `portainer_data`, `miniflux-rss_miniflux-db`, `paperless_redisdata`, `kitchenowl_kitchenowl_data` |
| `bumba/docker-volumes/` | 113 M | zitadel secrets + masterkey, traefik, score, and `_dumps/` |
| `bumba/named-volumes/` | 11 M | `portainer_data` + traefik/zitadel anonymous volumes |

**Databases were dumped, not copied live** — a filesystem copy of a running
postgres may not restore:

```
db-2026-09-14.sql.gz                  3.3K   memos schema + 1 row (verified: 10 COPY = 10 tables)
immich_postgres-2026-09-14.sql.gz     134M   the one that matters
kitchen-owl-db-1-2026-09-14.sql.gz    558K   27 tables with data
```

Deliberately excluded, both regenerate: `immich_model-cache` (786 M) and
`kopia/kopia-cache` (3.3 G). samson's containers were stopped for the copy
(plex's config is SQLite); mindy's were left running because the databases were
dumped instead.

### bumba = home-eu-central-1

Runs zitadel (`auth.wvl.app`), its postgres, score, the reverse proxy and
portainer. It was unreachable for three days: **SSH key auth failed and the
password did not work either**, because the image ships
`PermitRootLogin prohibit-password` — root may log in at the console but never
with a password over SSH. sshd advertises `publickey,password` regardless, which
is what made the diagnosis slow.

Recovered via: Hetzner Cloud panel -> **Reset root password** -> **Console**
(VNC) -> `tailscale set --ssh`. `set` rather than `up` matters — it enables SSH
without re-authenticating, so nothing long has to be typed into a VNC window
that has no clipboard.

**Postgres data lives on the attached Hetzner volume**, reached through a
symlink that makes it invisible to `du`:

```
/docker-volumes/db/data -> /mnt/HC_Volume_103225027/db/data/
```

`du -sh /docker-volumes/db` reports 8 K and `docker inspect` shows a bind to an
apparently empty path; `docker ps -s` confirms the container's writable layer is
53 B. The data is properly persisted — 214 MB on a 100 GB volume, 94 GB free.

**It is not big enough for the migration as it stands.** The data that would move
to Hetzner is ~118 GB (photos 65 G + audio 52 G + documents), against 94 GB
available.

At Hetzner's **EUR 0.069212/GB/month**:

| size | EUR/month | EUR/year | headroom over 118 GB |
|---|---|---|---|
| 100 GB (current) | 6.92 | 83 | **does not fit** |
| **150 GB** | **10.38** | 125 | 27% |
| 200 GB | 13.84 | 166 | 69% |
| 250 GB | 17.30 | 208 | 112% |

**Start at 150 GB** — +EUR 3.46/month on what is already being paid. Volumes
resize online in minutes (expand in the panel, then `resize2fs`) but never
shrink, so there is no reason to pre-pay for headroom that can be added the day
it is needed.

For scale: the EUR 450 replacement drive that was decided against is ~3.5 years
of a 150 GB volume — but the volume also deletes the NFS-over-WAN failure class
and never needs replacing.

Location constraint: this volume is attached to **bumba**, while immich and
filebrowser run on **mindy**. Hetzner volumes only attach to servers in the same
location — check `hcloud server list -o columns=id,name,location` before planning
to move it rather than provisioning a new one on mindy.

Dump: 113 MB gzipped, 173 `COPY` blocks, 3 databases.

| database | size |
|---|---|
| memos | 112 MB |
| zitadel | 25 MB |
| score | 13 MB |

**RESOLVED 2026-09-14: memos had been running empty.** The container was moved
from bumba to mindy without its data. mindy's DSN reads
`postgresql://memos:...@db:5432/memos` — mindy's *own* postgres, which held a
single `system_setting` row. All 45 notes, 39 attachments and 3 users were
sitting untouched in bumba's database.

Nothing was lost, and the fix was a migration rather than a restore:

```bash
# bumba
docker exec database-db-1 pg_dump -U postgres -d memos --clean --if-exists | gzip > memos.sql.gz
# mindy — DROP and CREATE, not --clean
docker exec db psql -U postgres -c "DROP DATABASE memos; CREATE DATABASE memos OWNER memos;"
zcat memos.sql.gz | docker exec -i db psql -U postgres -d memos
```

**`--clean --if-exists` alone was not enough.** bumba's memos was schema 0.25.1
(table `resource`); mindy's was 0.26.2 and had already created `attachment`.
`--clean` only drops objects the dump mentions, so `attachment` survived and
memos crash-looped applying `rename_resource_to_attachment` against a name that
was already taken. Dropping and recreating the database gave the restore a
genuinely empty target, after which memos migrated 0.25.1 -> 0.26.3 on startup
by itself.

Side finding: the restore logged `role "databasus-41ec78f0" does not exist`
repeatedly. **databasus creates per-backup roles inside the databases it backs
up**, and those roles do not exist on other hosts. Harmless here (it affects
GRANTs, not data) but it will matter when reconciling roles during the Hetzner
migration.

Follow-up once verified in the UI: drop the orphaned `memos` database on bumba,
reclaiming 112 MB of its 214 MB postgres footprint and removing the ambiguity
about which copy is authoritative.

**Tailscale SSH is in ACL "check" mode** — samson -> bumba prompted for browser
authentication. Fine interactively, but it will block unattended jobs and the
OpenTofu docker provider. Set that ACL rule to `accept` for own-devices.

### Things this turned up

- **`filebrowser` does not use postgres.** `FILEBROWSER_DATABASE=/home/filebrowser/data/database.db`
  — a local file in the 548 K volume. Its postgres role is vestigial.
- **`kitchenowl` exists twice**: a database inside the shared `db` with **zero
  tables**, and the live one in `kitchen-owl-db-1`. Drop the empty one before
  somebody restores the wrong one.
- **Portainer's data is a named volume**, not under `/docker-volumes`. Compose
  files come back from git; the stack *configuration* that points at that git
  does not. It lives only in `portainer_data`.
- **SSH keys were not set up between hosts.** samson could not reach mindy.
  Fixed with a root key; `tailscale up --ssh` would remove the problem class.

## Open items

- [ ] `sdg` has a corrupt journal but reports `Filesystem state: clean`.
      `e2fsck -f /dev/sdg1` would likely recover 4.5 TB of usable space.
      Contents unknown — probably more Synology archives.
- [ ] NVMe still carries Synology leftovers (`linux_raid_member` `Syno:3`, LVM,
      bcache), unmounted and unused — 238 GB doing nothing.
- [ ] Move `sdh` to a USB 3.0 port before using it for rotation.
