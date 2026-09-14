# Array surgery: RAID10 (4 drives) → raid1 (3 drives)

Removing `WSD320VH` (btrfs `devid 1`) without replacing it.

Context: [`../incidents/2026-08-06-array-overheating.md`](../incidents/2026-08-06-array-overheating.md)

## Why

`WSD320VH` is failing: 53,656 reallocated sectors (normalized 23 against a
failure threshold of 10) and a pending-sector count that keeps climbing under
ordinary load — 80 → 2,016 → 344 → 376 over three days. It was cooked at 94 °C
for five months by a bay fan that never ran.

**It is not being replaced.** An 8 TB drive is ~€450, and the array holds 8.3 TB
of media that is explicitly replaceable plus ~119 GB that lives on the Hetzner
Storage Box anyway. Buying redundancy for Plex rips is the wrong trade.

## Why raid1 and not single

`single` across 3 drives gives 21.8 TiB and no redundancy. raid1 gives 10.9 TiB
and survives a drive failure.

The off-site backup drive is refreshed roughly **every 4 months**. On `single`, a
drive failure would mean fetching the drive from family, a 13-16 hour restore,
and losing up to four months of additions. On raid1 it means carrying on while a
replacement is ordered. With three 7.27-year-old drives that ran five months at
94 °C, that trade is worth 11 TiB of unused capacity.

Capacity: 3 × 7.28 TiB = 21.84 TiB raw → **10.92 TiB usable**, against 8.39 TiB
in use. ~2.5 TiB of headroom. When that gets tight, a fourth drive is a capacity
purchase made deliberately — not a €450 emergency with a dying disk in the array.

## Preconditions

- [x] Full backup to the 14 TB USB drive — 8.4 TB, 9 subvolumes
- [x] Backup scrubbed: 8.39 TiB, **no errors found**, 10:48:35
- [x] Restore verified: `diff -r` on `gezin-officieel` → IDENTICAL
- [x] OMV monthly btrfs scrub disabled (`OMV_BTRFS_SCRUB_ENABLED="no"`)
- [x] SMART monitoring live and delivering mail

---

## Procedure

RAID10 requires ≥4 devices, so the profile must be converted **before** the
device can be removed. raid1 keeps two copies throughout — the array is never
unprotected during either step.

### 0. Reduce contention

kopia on mindy walks the whole tree over NFS and is the heaviest reader of the
failing drive. Stop it for the duration:

```bash
# on mindy
docker stop kopia
```

Leave NFS itself running — filebrowser and immich depend on it.

### 1. Convert the profile (long)

```bash
M=/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300
sudo systemd-run --unit=btrfs-convert \
  btrfs balance start -dconvert=raid1 -mconvert=raid1 "$M"
```

Rewrites all 8.39 TiB. Expect **12-24 hours**. Monitor:

```bash
sudo btrfs balance status -v "$M"
journalctl -u btrfs-convert -f
```

Resumable — `btrfs balance pause` / `resume` / `cancel` all work, and a cancelled
balance leaves a consistent filesystem.

Verify before continuing:

```bash
sudo btrfs filesystem df "$M"      # want Data,RAID1 and Metadata,RAID1
```

### 2. Remove the device (long)

```bash
sudo systemd-run --unit=btrfs-remove btrfs device remove /dev/sdb "$M"
```

**Check the serial first** — device letters shifted twice during this incident:

```bash
lsblk -d -o NAME,SERIAL | grep -i WSD320VH
```

Relocates `devid 1`'s chunks onto the other three. Several hours.

### 3. Verify

```bash
sudo btrfs filesystem show                 # 3 devices, no MISSING
sudo btrfs filesystem usage "$M"           # ~10.9 TiB usable, 8.39 TiB used
sudo btrfs device stats "$M"
```

### 4. Restore normal operation

```bash
# re-enable the monthly scrub — correct practice on a healthy array
sudo sed -i 's/^OMV_BTRFS_SCRUB_ENABLED=.*/OMV_BTRFS_SCRUB_ENABLED="yes"/' \
  /etc/default/openmediavault
sudo chmod +x /etc/cron.weekly/openmediavault-scrub_btrfs \
              /etc/cron.monthly/openmediavault-scrub_btrfs
run-parts --test /etc/cron.monthly          # confirm it is listed again

# on mindy
docker start kopia
```

Then in the OMV UI: *Storage → S.M.A.R.T. → Devices* — **disable monitoring for
`WSD320VH`** before physically removing it, or smartd will keep testing and
alerting on a drive that is no longer part of anything.

### 5. Refresh the off-site copy

The surgery rewrites metadata across the array. Content is unchanged, so this
should take minutes:

```bash
sudo btrbk -c /etc/btrbk/btrbk.conf dryrun     # expect >>> incremental
sudo btrbk -v run
sudo umount /mnt/backup-14t
```

Then the drive goes back off-site.

---

## What to expect during the run

- **Thousands of `critical medium error` and `read error corrected` messages** from
  `sdb`. Normal — btrfs repairs each from its raid1 mirror as it reads.
- **Daily SMART emails** about `WSD320VH`'s pending-sector count. Correct
  behaviour; it stops when the drive leaves.
- **Monit alerts on CPU I/O wait > 95%.** Also expected — this is hours of
  sustained I/O. Do not let it train you to ignore the channel that was only just
  repaired.

The one line that matters, which should stay silent throughout:

```bash
sudo journalctl -k -f | grep -E 'unable to fixup|csum failed'
```

Anything there is a block that exists nowhere recoverable. Stop and investigate.

## If `sdb` dies mid-operation

Not a disaster — raid1 keeps two copies throughout, so the array degrades rather
than loses data:

```bash
mount -o degraded ...                     # required to mount with a device missing
btrfs device remove missing "$M"          # finish the removal
```

And there is a verified 8.4 TB copy on the USB drive regardless.
