# Incident: samson array degraded — drive bay fan not running

**Started:** 2026-08-06 ~11:30 CEST **Detected:** 2026-08-09 10:24 (three days later, by a user-facing symptom)
**Root cause identified:** 2026-08-10 **Status:** server powered off pending hardware fix

Full debugging session: [`2026-08-06-transcript.md`](./2026-08-06-transcript.md)

---

## Summary

The fan in samson's 4-bay trayless hot-swap rack
([Reichelt 190808](https://www.reichelt.com/be/nl/shop/product/4x_3_5-inch_houderloos_sata_wisselframe-190808),
installed March 2026) was not running. Four 7200 rpm IronWolf drives sat in a sealed aluminium cage with no airflow and
reached **80–90 °C** (peak 94 °C) against a 70 °C rating.

One drive (`sde`) dropped off the SATA bus, another (`sdd`) began failing reads. That degraded the btrfs RAID10, which
broke OMV's shared folders, which emptied the NFS exports, which hung filebrowser on mindy.

**No data was lost.** All irreplaceable data was verified restorable from the kopia repository at Hetzner.

### Failure chain

```
drive bay fan not running
  → drives at 80–94 °C (rated 70 °C)
    → sdd: unrecoverable read errors (heat + its own bad SATA cable)
    → sde: dropped off the bus entirely
      → btrfs RAID10 degraded, 1 of 4 devices missing
        → OMV: "Invalid device file '<missing disk>'"
          → shared-folder bind mounts never established
            → /export/* are empty stubs on the root filesystem
              → NFS exports empty directories to mindy
                → filebrowser blocks forever in os.Stat() at startup
                  → drive.wvl.app unreachable
```

---

## Timeline

| when                   | what                                                                                                                                                                                    |
|------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| ~2018–2019             | Original build. 4× Seagate IronWolf ST8000VN0022 8 TB.                                                                                                                                  |
| 2026-02                | Synology DiskStation fails (enclosure, not drives).                                                                                                                                     |
| 2026-03                | Migrated to Dell OptiPlex + OMV 8.5.5. Drives moved into the 4-bay rack, wiped, restored from Synology HyperBackup. **Fan very likely never ran from this point** — see evidence below. |
| 2026-08-06 11:30–12:59 | `sdd` throws repeated `Medium Error / Unrecovered read error`. A btrfs scrub repairs each one from the mirror copy.                                                                     |
| 2026-08-06 12:05:41    | mindy logs its first `nfs: server 100.71.248.106 not responding, still trying`. Caused by sdd's multi-second read retries stalling the NFS server.                                      |
| (unknown, after 08-06) | `sde` disappears from the SATA bus entirely.                                                                                                                                            |
| 2026-08-07 → 08-09     | NFS stalls recur nightly at 00:05 / 02:05 / 03:05 / 05:05 — kopia's tree walk over NFS from mindy.                                                                                      |
| 2026-08-09 09:40:42    | filebrowser's `[DB_MAINTENANCE]` job starts and never completes.                                                                                                                        |
| 2026-08-09 10:24       | Login failures noticed (401s). OIDC login itself still worked.                                                                                                                          |
| 2026-08-09 10:28:53    | filebrowser container restarted → hangs at startup.                                                                                                                                     |
| 2026-08-09 11:32:57    | Restarted again → hangs identically.                                                                                                                                                    |
| 2026-08-09 21:21       | SMART on `sdd` shows **82 °C**, `FAILING_NOW`.                                                                                                                                          |
| 2026-08-10             | Fan observed not spinning. Server powered off.                                                                                                                                          |

---

## Evidence

### The fan never ran, rather than failed recently

Minimum recorded temperatures: **sdb 76 °C, sdc 86 °C, sdd 79 °C.** If the fan had ever worked there would be a much
lower minimum in the history. Combined with a March purchase date, the most likely cause is a connection issue, not a
failed part.

The rack requires **2× 15-pin SATA power connectors**. If only one was connected, drives spin up normally and the fan
never does — silent, with no symptom until SMART is read.

**The fan switch is ruled out.** The rack has no on/off — only high/low (set to **high**) and an HDD-LED enable. A fan
set to high that isn't turning is either unpowered or dead.

Remaining causes, in order: both SATA power leads connected → fan blocked by a cable → dead or seized fan. Diagnostic:
**spin it by hand.** Free and smooth = no power, chase connectors. Stiff or gritty = failed bearing, and it is under
warranty since March.

### The cage is a thermal island

Case air is fine. The NVMe cache SSD reads ~30 °C, implying ambient around 27–28 °C inside the OptiPlex — while drives a
few centimetres away sit at 90 °C.

That is not a contradiction, it is the signature of the fault. The rack is a **sealed aluminium box**: with the fan dead
there is no air exchange, so the ~36 W the four drives dissipate accumulates inside the cage instead of dispersing into
the case. A 60 °C rise over ambient for 36 W trapped in a small enclosure is expected. 28 + 60 ≈ 90, which is sdc.

A whole-case airflow problem would show a much smaller delta. A large delta between case air and drive temperature means
one enclosure isn't venting.

**This gives a clean pass/fail test after the repair:** with case ambient unchanged at ~28 °C, the drives should sit
**under 40 °C**. If they are still above ~45 °C with the fan turning, something else is wrong — stop before returning
the array to service.

### Storage controller and cabling

Drives are on an **LSI 9211-8i, P20 IT mode**, via **2× SFF-8087 → 4× SATA forward breakout cables**. This is the
correct card for the job and is not itself suspect.

It also explains the log format: `sd 0:0:2:0` with SCSI sense keys (`Sense Key : Medium Error`) is the `mpt2sas` driver
presenting drives as SCSI targets on a single host, not a fault indicator.

Two controller-adjacent things do matter:

- **Firmware revision.** "P20" is not specific enough. Releases `20.00.00.00`–`20.00.02.00` have documented bugs that
  drop drives off the bus under load; the known-good build is **`20.00.07.00`**. Check with
  `cat /sys/class/scsi_host/host0/version_fw`.
- **Breakout cable lanes.** `sdd` has 55 UDMA CRC errors while sdb and sdc have zero. CRC errors are link-layer — that
  is one lane of one cable, not the drive and not the HBA. **Record which drive sits on which cable and lane. The
  question that matters: are `sdd` and `sde` on the same cable?**

### Correction: the drives were not cooking the HBA

An earlier working theory held that 90 °C drives were heating the 9211-8i and causing it to drop devices. The ~28 °C
case air disproves it — withdrawn.

The card still warrants a €5 fan on its heatsink (the SAS2008 is specified for ~200 LFM of forced air it never gets in a
desktop), but as a precaution rather than a leading suspect. The OptiPlex MT has rear exhaust and CPU airflow, so it is
likely warm rather than critical.

### Revised suspect ranking for `sde`

1. **Breakout cable lane** — shares a cable with the only drive showing CRC errors
2. **Strained SATA power connector** — the rack's power leads are short and under tension; a millisecond power
   interruption makes a drive vanish exactly this way
3. **Early P20 firmware**
4. HBA thermals — demoted, see above

### Power supply

Original OptiPlex PSU, single supply for system and array.

|                           | 12 V draw           |
|---------------------------|---------------------|
| ST8000VN0022 spin-up peak | ~2.0 A (~24 W) each |
| operating                 | ~9 W each           |

Four drives spinning up simultaneously is ~8 A / 96 W of transient — cheap trayless racks do not stagger spin-up. Steady
state is ~36 W for the drives plus ~120–150 W for an i7-3770 system, against a 240–290 W OptiPlex MT supply. Adequate,
if not generous.

Two reasons to believe the PSU is not the cause here: it has booted reliably for five months, and `sde` dropped
**mid-operation**, where current is a third of spin-up.

If the array is expanded, add a second PSU with an **`add2psu` adapter** (~€5–10) so both supplies sequence together and
grounds are bonded. Never jumper PS_ON manually, and never split rails across supplies for one drive. For the short
cable runs, use **SATA power extensions**, and if adapting from Molex use **crimped/soldered adapters only** — moulded
Molex-to-SATA adapters are a fire hazard.

### Drive state at shutdown

| device | serial    | temp  | max | reallocated | UDMA CRC | notes                                             |
|--------|-----------|-------|-----|-------------|----------|---------------------------------------------------|
| sdb    | ZA1EFL3P  | 80 °C | 94  | 24          | 0        | clean link, some media damage                     |
| sdc    | ZA1EGFTL  | 90 °C | 94  | 8           | 0        | hottest                                           |
| sdd    | ZA1EGG4T  | 82 °C | 94  | **0**       | **55**   | bad SATA cable, pristine media                    |
| sde    | *unknown* | —     | —   | —           | —        | absent from bus; serial is whichever isn't listed |

All 63,721 power-on hours (7.27 years). All three present drives `FAILING_NOW` on attribute 190 (airflow temperature).

**`sdd` is not a failing disk.** Zero reallocated sectors, zero pending, extended self-test clean at 60,046 h. btrfs
*rewrote* every bad block during the Aug 6 scrub; had the media been defective those rewrites would have forced
reallocations. Its 55 UDMA CRC errors — and it is the only drive with any — point at its SATA cable, not its platters.

`sde` vanishing entirely is more characteristic of a **power interruption** than thermal stress. The rack's power cables
were noted as short and under tension, which is a plausible cause of intermittent contact.

### Filesystem state

```
Label: none  uuid: 25d0f3ec-68a9-4ce0-891e-0966088e5300
    Total devices 4 FS bytes used 8.39TiB
    devid 1 size 0 used 0 path <missing disk> MISSING
    devid 2,3,4  /dev/sdb,sdd,sdc

Data,RAID10:     Size:8.39TiB, Used:8.38TiB (99.83%)
Metadata,RAID10: Size:10.50GiB, Used:9.58GiB
Multiple profiles: no
mounted: rw,relatime,degraded,space_cache=v2
```

RAID10 tolerates exactly one missing device, so **all data remained readable**. Two constraints while degraded:

- Data chunks are 99.83 % allocated and btrfs RAID10 needs ≥4 devices, so **no new chunk can be allocated** — the
  filesystem is effectively unwritable.
- The mount carries `degraded`. **Without that option it will not mount at all** on the next boot.

### Why filebrowser hung rather than erroring

filebrowser-quantum v1.5.0, `backend/common/settings/config.go` → `setupSources()`:

```go
exists := utils.CheckPathExists(realPath) // os.Stat
if !exists {
logger.Warningf("source path %v is currently not available", realPath)
}
```

That warning **never appeared in the logs**, which proves `os.Stat` was blocking, not returning "not found". A `hard`
NFS mount against an unresponsive server blocks indefinitely.

Startup logs stop after `OIDC Auth configured successfully` and never reach the unconditional
`Initializing FileBrowser Quantum` banner — the process never opened its HTTP listener. Being stuck in that syscall also
meant it could not handle SIGTERM, so `docker restart` had to SIGKILL it.

---

## Backups

**Verified restorable on 2026-08-09** — restored `gezin-officieel` from the kopia repository on the Hetzner Storage Box:
608 MB / 330 files, an exact match to both the live `du` and the snapshot metadata.

### Data on the array

| directory                                    | size      |
|----------------------------------------------|-----------|
| media                                        | **8.3 T** |
| photos                                       | 65 G      |
| audio                                        | 52 G      |
| backups                                      | 1.4 G     |
| gezin-officieel                              | 608 M     |
| wim                                          | 2.1 M     |
| sara, gezin-officieel-archive, audio-archive | 0         |

Media is **98.6 %** of the array. Everything else totals ~119 GB.

### Coverage

All non-media data is fully backed up. Media is ~810 GB of hand-picked directories out of 8.3 TB — deliberate, covering
the irreplaceable items (childhood series not available on any media).

The zero-byte snapshots for `sara` / `gezin-officieel-archive` were initially suspected to be unmounted-mountpoint
artifacts. They are not — `du` confirms those directories are genuinely empty.

### Defects found in the kopia setup

1. **Sources were keyed `root@1da0a4624124`** — the container ID. Kopia identifies sources as `user@host:path`, so every
   container recreation minted a new identity and reset history. 57 of 65 sources hold exactly one snapshot; nothing
   predates Jul 31. *Fixed in the repo by pinning `hostname:`.*
2. **Most sources have no schedule** — only `photos` shows a real cadence (Aug 1→3→4→5→6).
3. **Media coverage is 57 hand-picked directories, not a tree**, with at least one overlapping pair (`Plonsters (1987)`
   and `Plonsters (1987)/Season 01`). Anything added outside those exact paths is silently unprotected.
4. **`/docker-volumes/kopia/data/audio-archive` is in mindy's fstab but was never mounted** — no systemd unit, absent
   from `findmnt`. Harmless today because the directory is empty; would silently skip backups the day it is used.

### Retention hazard

The Aug 6 `photos` snapshot holds the `monthly-1` and `annual-1` tags. Those attach to the most recent snapshot in each
period. **Do not run kopia while `/export` is empty** — a fresh empty snapshot would claim those tags and, with
`keepLatest=10`, roughly ten empty runs would prune the only good 69.3 GB photo backup. kopia was stopped on mindy for
this reason.

---

## Outstanding actions

### Hardware — while the case is open

- [ ] **Both SATA power leads** connected to the rack (needs 2× 15-pin) — top suspect for the fan
- [ ] **Spin the fan by hand** — free = unpowered, stiff = dead bearing (warranty, bought March)
- [ ] **Map breakout cables**: which drive on which cable and lane. *Are `sdd` and `sde` on the same cable?*
- [ ] **Replace `sdd`'s lane** (serial ZA1EGG4T) — 55 CRC errors, only drive affected
- [ ] **Reseat `sde`**, record its serial (the one that isn't ZA1EFL3P / ZA1EGFTL / ZA1EGG4T) and note how taut its
  power feed is
- [ ] **SATA power extensions** for the short leads — crimped adapters only, never moulded Molex-to-SATA
- [ ] Optional, €5: small fan on the 9211-8i heatsink

### Hardware — after power-on

- [ ] **Drives under 40 °C?** Pass/fail for the whole diagnosis. Above ~45 °C with the fan turning means stop and
  investigate
- [ ] **HBA firmware:** `cat /sys/class/scsi_host/host0/version_fw` — want `20.00.07.00`, early P20 drops drives
- [ ] Confirm `degraded` is in fstab, or the array will not mount on boot
- [ ] `smartctl -t long` on every drive, only once cool

### Recovery

- [ ] If `sde` returns and all four pass: `btrfs scrub`, no replacement needed
- [ ] If not: `btrfs replace start 1 /dev/sdX <mountpoint>` — **not** `btrfs device delete missing` (cannot allocate
  RAID10 chunks with 3 devices) and **not** `balance` (rewrites 8 TB with no redundancy)

### Prevention

- [x] OMV → Storage → S.M.A.R.T. → enable daemon, temperature threshold ~55 °C, email notification
      — **done 2026-09-13.** `enable=1`, `tempmax=55`, `tempdiff=10`, all six devices
      monitored by `by-id` path. Verified delivering. See the 2026-09-13 section.
- [x] OMV → System → Notification → configure SMTP so alerts arrive
      — **done 2026-09-12, fixed 2026-09-13.** Configuring it was not enough; 23 messages
      sat undelivered behind `smtp_tls_wrappermode = yes` on port 587.
- [x] Schedule periodic self-tests per drive — **done 2026-09-13**, after ~3.4 years of none
- [ ] Service-level monitoring (e.g. Uptime Kuma on mindy against drive.wvl.app / photos.wvl.app) — nothing in the stack
  noticed a three-day outage. Compose written at `mindy/uptime-kuma/`; still needs a
  portainer stack creating (new stacks do not auto-deploy). Add a check that
  `postqueue -p` is empty — a filling mail queue had nothing watching it.

### Backups

- [ ] Review the 57 hand-picked media sources against what is actually irreplaceable
- [ ] Set retention/compression policies on new sources after the hostname change
- [ ] Deploy `samson/kopia` (client) once `/export` is populated again — see `samson/kopia/README.md`

---

## Repository changes made during this incident

| file                               | change                                                                                                                                                                                                                                         |
|------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `mindy/fstab`                      | new — documents the host's NFS mounts, hardened with `x-systemd.automount` + `mount-timeout=15` so an unavailable share fails fast instead of hanging filebrowser. Requires `bind-propagation=rslave` on the docker binds; **not yet applied** |
| `mindy/kopia/docker-compose.yml`   | TLS instead of `--insecure`; bind moved from `0.0.0.0` to the Tailscale address (the repository API was reachable over cleartext HTTP from the internet); `hostname: mindy` pinned                                                             |
| `samson/kopia/docker-compose.yaml` | new — kopia repository *client*, scans local disk, proxies through mindy so the Storage Box stays Hetzner-internal                                                                                                                             |
| `samson/kopia/.env`                | new — cert fingerprint and snapshot interval                                                                                                                                                                                                   |
| `samson/kopia/README.md`           | new — four-phase migration runbook with rollback                                                                                                                                                                                               |

None of these are deployed.

---

## Architecture notes

Worth revisiting once the hardware is stable.

**The array protects the wrong thing.** 98.6 % of it is media; the irreplaceable data is ~119 GB plus ~810 GB of curated
media, roughly 930 GB total. RAID10 across 4× 8 TB is being paid for to protect Plex rips.

**Drive economics (Aug 2026 prices).** 8 TB ≈ €450, up from €250 seven years ago. Replacing all four every five years ≈
€30/month. A Storage Box sized for ~1 TB is a fraction of that with no replacement cycle.

**Candidate shape:**

```
~930 GB  → Hetzner (Storage Box or small volume), apps read/write here
~7.5 TB  → home, no redundancy, replaceable
```

with backups pulled Hetzner → home (uses the fast direction of a residential line) plus the offline external drive.

**If the home NAS is retired entirely**, the second copy has to be a *different provider* (Backblaze B2 / R2 / Wasabi, ~
€6–15/month for 1 TB), not a second Storage Box — two boxes share one Hetzner account and so share the account-level
failure modes, which are the likelier ones. Mirror the kopia repository with `rclone sync`; use object lock to replace
the air-gap property of the offline drive.

**The Storage Box has real constraints:** max 10 simultaneous connections, no NFS (SMB/CIFS and WebDAV only), and
throughput that varies with other tenants on the host.

**Do not put the kopia repository on the same Storage Box that holds the live files.** That collapses two independent
locations into one.

**NFS over a residential WAN was the wrong tool** regardless of the disks. `hard` mounts with `timeo=900` mean an
unavailable server blocks callers for 90 s per retry, forever. Either move compute to the data, or use
`x-systemd.automount` so mounts fail fast.

### Chassis: separating storage from compute

Preferred direction — make the array a self-contained unit with its own power and cooling, and treat compute as
swappable (four spare OptiPlexes on hand). This incident supports it: every contributing fault was a property of the
enclosure, not the machine.

The interconnect is the decision that matters:

|                         | verdict                                                                                                        |
|-------------------------|----------------------------------------------------------------------------------------------------------------|
| USB DAS                 | **avoid** — USB-SATA bridges drop drives, hide SMART, port multipliers misbehave. Recreates this exact failure |
| eSATA + port multiplier | works, needs host FIS support, shared bandwidth                                                                |
| SAS, SFF-8088/8644      | correct — true passthrough, real SMART, hot-swap                                                               |

**The existing 9211-8i already covers this.** Eight ports, four in use, so the array can double without a new card.
Taking it external needs only an **SFF-8087 → SFF-8088 bracket adapter** (~€15–25), not a 9207-8e. The enclosure itself
is the only real purchase; used enterprise shelves (MD1200, D2600) are €150–250 but rack-mount, loud and ~100 W idle.

**Cheaper variant with most of the benefit:** make the *case* the durable unit — mid-tower, front 3.5" cage, 120/140 mm
intake, properly sized ATX PSU (~€100–150). Drives, cooling, power and cabling become permanent; the motherboard is the
swappable part. Drives can move to a DAS later unchanged. Check first whether the Dell board uses a standard 24-pin PSU
connector.

Caveat worth remembering: the i7-3770 is Ivy Bridge, launched 2012. Spare boards are genuinely useful, but don't buy an
expensive enclosure to wrap around compute that should be retired — the enclosure should outlive the OptiPlexes.

---

## Lessons

1. **A €10 fan failed silently for five months and cost a three-day outage plus thermal damage to four drives.** The gap
   was monitoring, not hardware.
2. **Zeroed SMART counters hide history.** `btrfs device stats` showed all-clean because the counters were zeroed on Aug
   9 07:35. The real story was only in the journal from Aug 6.
3. **Check the physical layer earlier.** Three days went into software diagnosis for a problem that was visible by
   opening the case.
4. **An untested backup is a hypothesis.** Restoring 608 MB took two minutes and converted the entire situation from
   frightening to merely annoying. The previous backup — a Synology HyperBackup archive — had already proven partly
   unreadable when it was needed in February.
5. **Measure at the right place.** Case ambient was a perfectly healthy 28 °C throughout. Every temperature that
   mattered was inside a sealed box six centimetres away. A component-level reading would have caught this in March; a
   case-level one never would have.
6. **Working theories need retracting out loud.** Two held during this investigation and were wrong: that `sdd` was a
   dying disk (SMART: zero reallocated sectors — it was heat and a bad cable), and that the hot drives were cooking the
   HBA (case air disproved it). Both are recorded above rather than quietly dropped, because the reasoning that produced
   them will recur.

---

# Recovery: 2026-09-11

**Bay replaced, server powered back on after 32 days off.** Array is healthy and
online. One drive needs replacing. A second, unrelated outage was found: kopia
had been dead for five weeks.

## The thermal fix worked

| | before (2026-08-10) | after (2026-09-11) |
|---|---|---|
| drive temps | 80–94 °C | **31–34 °C** |
| attribute 190 | `FAILING_NOW` on all three | `In_the_past` |

Case ambient is unchanged at ~26–28 °C, so the pass/fail test set out above —
*drives under 40 °C or stop* — passes with 6 °C of margin. The sealed-cage
diagnosis was correct and the new bay resolved it.

### "The fan never ran" is now confirmed, not inferred

The original evidence was indirect: no low minimum temperature anywhere in the
history. The replacement drive's device statistics state it outright:

```
Time in Over-Temperature: 215216      (minutes, per ACS)
```

3,587 hours = **149.5 days**. Counted back from the 2026-08-10 shutdown that
lands on ~13 March 2026 — the month the drives were moved into the rack. The fan
never ran for the entire life of the installation.

### Reading the SCT temperature history: a trap

`smartctl -x` reports 88–94 °C stamped `2026-09-06` … `2026-09-11`, which looks
like a second overheat. It is not. The SCT log stores no timestamps; smartctl
back-projects them from *now* assuming contiguous sampling, so a month of
downtime shifts every historical sample forward into the present. The
authoritative counter for the current power cycle is:

```
Power Cycle Min/Max Temperature:     26/33 Celsius
```

## The array came back clean

All four devices enumerated. No `MISSING`, no `degraded` mount option, all nine
`/export/*` subvolumes bind-mounted by OMV without intervention.

```
Device size: 29.11TiB   allocated: 16.81TiB   unallocated: 12.30TiB
Free (estimated): 6.17TiB
```

**The "effectively unwritable" constraint recorded above was an artifact of being
degraded, not of being full.** btrfs RAID10 needs four devices to allocate a new
chunk; with the fourth back it allocates normally again. The 99.83 % figure
describes chunks already allocated, not the filesystem.

`btrfs device stats` clean on all four. HBA firmware reads `20.00.07.00` — the
known-good build — so that suspect is cleared outright.

## Correction: `sde` was a failing disk, not a cable or a power fault

The missing drive is **WSD320VH**, an `ST8000VN004-2M2101` at 41,591 hours — a
different model and 22,000 hours younger than the three `ST8000VN0022`s. Its
serial was never recorded above because it was absent from the bus. It is btrfs
**devid 1**. Note the device letters all shifted on this boot; map by serial, not
by letter.

| | WSD320VH (sdb) | ZA1EGG4T (sdc) | ZA1EGFTL (sdd) | ZA1EFL3P (sde) |
|---|---|---|---|---|
| reallocated | **51,944** (norm 21, thresh 10) | 0 | 8 | 24 |
| current pending | **80** | 0 | 0 | 0 |
| offline uncorrectable | **80** | 0 | 0 | 0 |
| UDMA CRC | 0 | **55** | 0 | 0 |

The `Pending Defects` log dates every defect precisely:

| defect cluster | appeared at lifetime hour |
|---|---|
| LBA 6878776–6878799 | 41,510 |
| LBA 9819248–9819254 | 41,519 |
| LBA 4102224–4102231 | 41,544 |

The drive is at 41,591 hours. **All 80 defects appeared in its final 81 powered
hours** — during the overheat, not spread across 4.7 years. Every defect LBA is
below 10 million, i.e. the first ~5 GB of an 8 TB platter: tightly localized
damage, likely one head or zone.

**Both theories in the "Revised suspect ranking for `sde`" above are wrong.** The
link is provably clean:

```
Number of Interface CRC Errors:  0
SATA Phy Event Counters:         all zero except 1 COMRESET
Resets Between Cmd Acceptance and Completion:  18
Number of Hardware Resets:       49
```

A clean link with command timeouts and resets. The drive did not vanish because
of a breakout-cable lane or a strained power connector — it vanished because it
was timing out on unreadable media and the HBA stopped waiting. Heat caused it;
the cabling was innocent.

`ZA1EGG4T`'s 55 UDMA CRC errors are unchanged this boot and remain unexplained.
That lane was never swapped. It has not been tested under load.

### Self-tests stopped running years ago

WSD320VH's last completed self-test was at lifetime hour **11,279**. It is at
41,591. Scheduled testing stopped roughly 3.4 years ago, in the Synology era, and
was never re-established after the March migration. Sixteen short tests, all
passing, then nothing.

## Second outage found: kopia had been dead for five weeks

`kopia` on mindy was in a restart loop:

```
error starting TLS server: open /app/config/kopia.cert: no such file or directory
```

**Cause: portainer redeploys every stack from git daily.** The TLS rewrite listed
in "Repository changes made during this incident" was committed in `42b301b`
(2026-09-04). Portainer pulled it and redeployed within a day. Phase 1 of
`samson/kopia/README.md` — the one-off certificate generation that must happen
*before* that compose can start — was never run. The container has failed on
every start since.

The line "None of these are deployed" was true when written and false
approximately 24 hours later. **In a GitOps repo, committing a change is
deploying it.**

No data was lost, and the crash loop turned out to be protective: a *running*
kopia snapshotting empty NFS mounts for five weeks would have rolled the
retention tags forward and aged out the photo backup, exactly as the "Retention
hazard" section warned. Verified intact:

```
root@1da0a4624124:/data/photos
  2026-08-06 05:00:21 UTC  69.3 GB  files:45390  (latest-1,hourly-1,daily-1,weekly-1,monthly-1,annual-1)
```

### The identity defect is contained, not fixed

`repository.config` records the identity used at connect time and still reads
`Username: root, Hostname: 1da0a4624124`. The `hostname: mindy` pin affects only
a *fresh* connect, so it does not rename existing sources. This is the preferred
outcome: the identity is now frozen rather than churning on every container
recreate, and keeping it preserves continuity with the existing snapshot history
and its retention tags. Renaming would orphan all of it. Address identity during
the samson migration instead.

### Still outstanding from the backup audit

- **`/docker-volumes/kopia/data/audio-archive` is still not mounted** on mindy —
  the mountpoint directory does not exist, so the fstab line fails silently.
  Defect #4, unchanged.
- `syncthing` runs on samson and is not in this repository. Deliberate — it is
  an experiment, not yet adopted. Worth committing if it stays, since an
  uncommitted container is invisible to portainer's redeploy and would not
  come back on its own after a rebuild.

## Repository changes made during recovery

| file | change |
|------|--------|
| `mindy/file-browser/docker-compose.yaml` | bind converted to long form with `propagation: rslave` + `create_host_path: true`. Required before the hardened fstab is applied: the automount is established after the container starts, and with default propagation the container keeps its empty pre-mount view — reintroducing the August symptom as a side effect of the fix. |
| `mindy/immich/docker-compose.yml` | same, for `${UPLOAD_LOCATION}` |
| `samson/kopia/.env` | `KOPIA_SERVER_CERT_FINGERPRINT` recorded from the Phase 1 cert |

## Additional lessons

7. **In a GitOps repo, committing is deploying.** A compose change with manual
   prerequisites must not be committed until those prerequisites exist. Five
   weeks of lost backups came from a config file that was correct, reviewed, and
   merged — and whose runbook step was never executed. Either do the manual step
   first, or write the change to fail safe when the prerequisite is absent.
8. **Two independent month-scale silent failures in one system.** The fan (five
   months) and kopia (five weeks). Neither was detected by anything; both were
   found by a human looking. The common cause is not hardware and not
   configuration — it is that nothing in this stack reports its own health.
9. **Read-only diagnostics are not always read-only.** `kopia server
   start --tls-generate-cert` also starts the source manager, which took a real
   snapshot of `/data/wim` during certificate generation. It was harmless only
   because `/data` was deliberately mounted in that throwaway container; without
   it the snapshot would have captured an empty tree and claimed the retention
   tags. Check what a "just generate a cert" command actually starts.

---

## 2026-09-11 evening: reboot after system updates

Shutdown failed to unmount the array:

```
umount: /srv/dev-disk-by-uuid-25d0f3ec-...: target is busy
Failed unmounting srv-dev\x2ddisk\x2dby\x2duuid\x2d25d0f3ec...mount
```

**A btrfs scrub was running.** systemd gave up and continued, so the filesystem
went down unclean — the 8-minute gap between boot `-1` ending 19:49:45 and boot
`0` starting 19:58:08. No harm done: it remounted normally, `corruption_errs 0`,
`generation_errs 0`. btrfs is CoW; this is the case it is built for.

### What started it: anacron catching up

```
Sep 11 16:49:56 anacron[13513]: Job `cron.monthly' started
Sep 11 16:49:56 omv-btrfs-scrub[18803]: Performing a scrub on all mounted Btrfs file systems.
Sep 11 16:49:56 kernel: BTRFS info (device sde): scrub: started on devid 1
```

`/etc/cron.monthly/openmediavault-scrub_btrfs` — a **stock OMV job**, nobody
configured it. samson was off for 32 days, so on boot anacron ran every missed
periodic job in sequence: `cron.daily` 16:39, `cron.weekly` 16:44,
`cron.monthly` 16:49.

OMV ships the same script in `cron.weekly` too, but each copy guards on the
configured period:

```sh
OMV_BTRFS_SCRUB_PERIOD=${OMV_BTRFS_SCRUB_PERIOD:-"monthly"}
[ "${OMV_BTRFS_SCRUB_PERIOD}" != "monthly" ] && exit 0
```

so with the default only one of the pair ever runs. Scrubs here are **monthly**,
next due ~11 October.

Disabled during recovery via `OMV_BTRFS_SCRUB_ENABLED="no"` in
`/etc/default/openmediavault`. That is the supported switch and it is a dpkg
conffile, so the setting survives package upgrades — unlike `chmod -x` on the
cron scripts, which the next `openmediavault` upgrade would silently revert,
re-arming the scrub with no indication anything had changed.

**Re-enable after `btrfs replace` completes.** Periodic scrubbing is correct
practice on a healthy array and is how latent corruption is caught while a good
mirror still exists to repair from. It is wrong only against a drive with no
spare sectors left.

Searching `/etc/cron.d` and `systemctl list-timers` is not sufficient to find
scheduled work on Debian. `run-parts` jobs in `/etc/cron.{daily,weekly,monthly}`
are invisible to both, and anacron makes them fire at boot rather than on the
clock.

`/etc/cron.d/openmediavault-clamdscan` was checked and contains no job lines —
clamd runs but scans nothing on a schedule.

### Result: no data loss

```
Duration: 3:06:41   Rate: 329.04MiB/s   (~3.5 TiB of 16.77 TiB, ~21%)
read_errors:          59952
corrected_errors:     59940
uncorrectable_errors:    12
csum_errors:              0
verify_errors:            0
```

Message tally across the whole boot:

```
   7430 fixed up error
    162 read error corrected
      0 unable to fixup
      0 csum failed
```

**The 12 "uncorrectable" errors are an artifact of the interruption**, not real
loss. btrfs emits `unable to fixup (regular) error at logical <N>` for every
genuinely unrecoverable block and there are none; `csum_errors` is zero, so
nothing failed checksum validation. Those 12 were in flight when the reboot
killed the scrub — counted, never retried. Every real failure was a hard I/O
error on `sdb`, and every one was repaired from its mirror.

### Correction: the damage is not localized

Recorded above: *"every defect LBA is below 10 million … tightly localized
damage, likely one head or zone."* **Wrong.** That described only the 80 defects
SMART had detected at the time. The scrub found failures across the whole
platter — sectors 1367873800, 4195088064, 4195521184, 9021381376, 9021384192.
The Pending Defects log was a floor, not a map.

### `WSD320VH` is collapsing

| | 2026-09-11 16:22 | 2026-09-11 20:05 |
|---|---|---|
| Reallocated_Sector_Ct | 51,944 (norm 21) | **53,656 (norm 20)** |
| Current_Pending_Sector | 80 | **2,016** |
| Offline_Uncorrectable | 80 | **2,016** |

Twenty-five times the pending sectors, from reading a fifth of the array. Failure
threshold on the normalized value is 10. It is still producing fresh read errors
under ordinary NFS load.

**Do not scrub again before the replacement.** The scrub reveals pre-existing
damage rather than causing it, but each repair forces a reallocation on a drive
with almost no spare pool left, and all that work is discarded when the device is
replaced. `btrfs replace` reads mirrors where the source is unreadable and writes
to the *new* disk, which is what this situation needs.

### Two suspects cleared

- **`ZA1EGG4T`'s UDMA CRC count is still exactly 55** after three hours of
  full-throughput scrub load. That lane had never been tested under load. The 55
  errors are historical, from the overheat period — not an active fault. The
  breakout-cable theory for this drive can be retired.
- **Thermals hold under sustained load.** 44–45 °C during the scrub, against
  32–34 °C idle and a 70 °C rating. The replacement bay is validated under real
  I/O, not just at idle.

### Other readers of the array

`clamd` is running and `/etc/cron.d/openmediavault-clamdscan` is installed. If it
is configured against the array that is a second scheduled full-surface read over
8.3 TB. Check and pause it until the replacement drive is in.

---

## 2026-09-13: why nothing noticed — the answer

The write-up above assumed monitoring was absent. It was not. It was **present,
configured, and disconnected at two separate links.**

### Link 1: the SMART sensor was switched off

```
/etc/openmediavault/config.xml
  smart.enable   = 0      <- SMART monitoring disabled
  smart.tempmax  = 0      <- no temperature threshold
smartd: enabled=not-found, active=inactive
```

while the notification list showed:

```
  smartmontools          enable=1
```

**The alert was armed; the sensor was never switched on.** OMV was fully prepared
to email about SMART problems and nothing was ever reading SMART to generate one.
That is why four drives ran at 90-94 C for five months in silence. Not a missing
feature and not a broken alert — one checkbox, off.

Fixed 2026-09-13: `enable=1`, `tempmax=55`, `tempdiff=10`.

**Gotcha worth knowing: the global toggle is not enough.** With SMART enabled and
`smartmontools.service` running, `/etc/smartd.conf` contained only a policy line
and no devices:

```
DEFAULT -a -o on -S on -T permissive -R 5! -R 197! -U 198+ -W 10,55,60 -n never,q
```

```
smartd: Configuration file /etc/smartd.conf parsed but has no entries
smartd: Monitoring 0 ATA/SATA, 0 SCSI/SAS and 0 NVMe devices
```

`DEFAULT` sets the policy applied *to* monitored drives; it selects none. Devices
are enabled individually under *Storage -> S.M.A.R.T. -> **Devices*** , a separate
tab from *Settings*. A daemon running with a correct policy and zero devices
looks healthy from every angle except its own log.

Devices enabled 2026-09-13 13:04. smartd now monitors all six devices by
`/dev/disk/by-id/` path -- which matters here, because device letters shifted
twice during this incident and by-id paths are immune to that.

**Verified working end to end** on its first pass:

```
smartd: Device: ...WSD320VH [SAT], 344 Currently unreadable (pending) sectors
smartd: Sending warning ... to van.laer.wim@gmail.com wim@wvl.app ...
smartd: Warning via /usr/share/smartmontools/smartd-runner ... successful
```

Sensor -> threshold -> event -> mail -> delivered. The first alert this machine
has ever generated about a disk by itself, and it correctly identified the
failing drive. The root cause of this incident -- *"a EUR 10 fan failed silently
for five months and cost a three-day outage plus thermal damage to four drives.
The gap was monitoring, not hardware"* -- is now closed rather than documented.

Still outstanding: **scheduled self-tests** (short weekly, long monthly per
drive, under *Storage -> S.M.A.R.T. -> Scheduled tests*). `WSD320VH`'s last
completed self-test was at lifetime hour 11,279 against 41,591 now -- roughly 3.4
years of no testing.

### Link 2: mail was generated but never delivered

Notifications were configured on 2026-09-12 (Mailgun, `smtp.eu.mailgun.org`).
Nothing arrived. 23 messages sat in the Postfix queue:

```
Cannot start TLS: handshake failure
TLS library problem: error:0A00010B:SSL routines::wrong version number
```

Cause — one line of postfix config:

```
relayhost             = [smtp.eu.mailgun.org]:587
smtp_tls_wrappermode  = yes     <- implicit TLS, belongs on 465
```

Port 587 expects plaintext then `STARTTLS`; postfix was sending a TLS ClientHello
immediately. `wrong version number` is the signature of speaking TLS at a
plaintext port. Both endpoints were healthy — `openssl s_client` negotiated
TLSv1.3 on 587 and TLSv1.2 on 465. CA certificates were present and current.

Fixed in the OMV UI (*System -> Notification -> Settings*, connection security
`STARTTLS`, port 587) rather than by editing `main.cf`, which OMV regenerates
via Salt.

### What the backlog revealed

The first delivered message, dated **2026-09-11 21:06** — the night of the
reboot:

```
Subject: [samson.home] Monitoring alert -- Resource limit matched samson
Description: cpu I/O wait of 99.6% matches resource limit [cpu I/O wait > 95.0%]
X-Mailer: Monit 5.34.3
```

**Monit caught it in real time.** 99.6% I/O wait was `sdb` blocking up to 7
seconds per bad sector (SCT ERC = 70) while kopia walked the array over NFS. A
correct alert, generated at the right moment, undeliverable for two days.

This host had more instrumentation than the original write-up credited — Monit on
resources, OMV's daily btrfs error check, apticron — all emailing, all blocked at
the same single point.

### Lesson

10. **Detection, reporting, delivery and noticing are four separate links, and
    this system broke a different one each time.** The fan: sensor off. kopia:
    nothing watching a crash loop. The btrfs errors: mail generated, delivery
    failed. Each layer worked right up to the boundary of the next. Testing a
    monitoring chain means exercising it end to end — a configured alert path
    that has never delivered a message is a hypothesis, exactly like an untested
    backup.

    Corollary: **monitor the monitor.** A Postfix queue silently accumulating for
    two days had nothing watching it. The Uptime Kuma push monitor in
    `mindy/uptime-kuma` alerts on *silence*, which is the only shape that catches
    a broken delivery path. Add a check that `postqueue -p` reports empty.

---

## 2026-09-14: `ZA1EGG4T`'s "failing" attribute is the same 55 errors again

With smartd finally running, it began reporting daily:

```
Device: ...ZA1EGG4T [SAT], Failed SMART usage Attribute: 184 End-to-End_Error.
```

Attribute 184 counts failures in the drive's internal data path and is one of the
attributes usually treated as a strong failure predictor. It is not one here.

```
184 End-to-End_Error   VALUE 045  WORST 045  THRESH 099  Old_age  FAILING_NOW  RAW 55
199 UDMA_CRC_Error_Count                                                       RAW 55
ATA Error Count: 55 — all at power-on lifetime 63642 hours
```

**Raw 184 equals raw 199 equals the ATA error count: 55.** Seagate increments 184
from the same data-path integrity failures that bump the CRC counter, and the
error log puts all 55 in a **single cluster at hour 63,642** — about 160 hours
before the drive's current lifetime, i.e. the August overheat. These are the same
55 errors already investigated and cleared above, surfacing under a second
attribute.

Everything else says the drive is sound:

- `VALUE` equals `WORST` — it has not moved since it first dropped
- type is `Old_age`, not `Pre-fail` — the drive does not classify it as predictive
- `SMART overall-health: PASSED`
- reallocated **0**, pending **0**, offline-uncorrectable **0**, reported-uncorrect
  **0**, command-timeout **0** — the cleanest media of the three survivors
- btrfs `corruption_errs 0` and zero csum failures across 1.1+ TiB rewritten
  through this drive during the raid1 conversion

`FAILING_NOW` means only that a normalized value (45) sits below its threshold
(99). The threshold is unusually high and these counters never decrease, so
**smartd will report this every 24 hours indefinitely.**

### The real risk here is alert fatigue

Two permanent daily alerts about known conditions — this one and `WSD320VH`'s
pending sectors — on a notification channel that did not deliver a single message
until 2026-09-13. That is precisely how mail from this host becomes something
nobody reads, which is the failure mode the whole incident was about.

Decide what to do **after** `WSD320VH` is removed, when only this one remains.
Suppressing attribute 184 for this specific drive (`-I 184` in smartd's per-device
options) is defensible once understood; muting smartd generally is not. Note that
OMV regenerates `/etc/smartd.conf`, so any such change belongs in OMV's per-device
settings, not a hand edit.
