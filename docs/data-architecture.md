# Target architecture: where the bytes live

Design notes from 2026-09-14. Not implemented. Companion to
[`iac-migration.md`](./iac-migration.md) — that one is about *tooling*, this is
about *data*.

Driven by the 2026-08 array incident ([
`../samson/incidents/2026-08-06-array-overheating.md`](../samson/incidents/2026-08-06-array-overheating.md)),
whose cascade ran entirely through `hard` NFS mounts over a residential WAN.
Moving the apps onto the same machine as their data deletes that failure class
rather than hardening it.

## Shape

```
Hetzner                                        home                         off-site
────────────────────────────────────────────────────────────────────────────────────
volume 150 GB   photos, audio, documents  ──►  samson: kopia repository  ──►  14 TB
  immich, filebrowser read/write locally       (versioned, on the array)      drive at
                                                                              family,
storage box     curated media archive    ◄──   samson: media 8.3 TiB    ──►  ~4-month
  ~1 TB, cheap bulk, write-once                (primary, plex reads local)     cadence
```

Note the arrows run **both ways**. This is not "everything moves to Hetzner".

## Data classes

| data                                                 | size   | changes?            | primary                      | backup                    | air-gap     |
|------------------------------------------------------|--------|---------------------|------------------------------|---------------------------|-------------|
| photos                                               | 65 G   | constantly          | **Hetzner volume**           | kopia → samson            | 14 TB drive |
| audio (active)                                       | ~15 G  | occasionally        | **Hetzner volume**           | kopia → samson            | 14 TB drive |
| **audio archive**                                    | ~29 G  | write-once          | **samson** (`audio-archive`) | → storage box             | 14 TB drive |
| documents (`gezin-officieel`, `wim`, `sara`)         | ~1 G   | occasionally        | **Hetzner volume**           | kopia → samson            | 14 TB drive |
| postgres (zitadel, score, memos, kitchenowl, immich) | ~350 M | constantly          | **Hetzner**                  | `pg_dump` → samson        | 14 TB drive |
| **curated media** (irreplaceable)                    | ~810 G | rarely, grows       | **samson**                   | **→ Hetzner storage box** | 14 TB drive |
| rest of media                                        | ~7.5 T | occasionally, grows | **samson**                   | *none — replaceable*      | 14 TB drive |

The curated set is the reverse flow: Belgian pre-2000 films and series that
cannot be re-acquired. It is served from home by plex, so it stays primary on
samson — but it needs an off-site copy that is not four months stale.

### The constraint nobody had measured: bumba is a `cpx11`

Established 2026-09-16 from `hcloud server-type list`:

| server | type | cores / RAM / disk | orderable in `fsn1`? |
|---|---|---|---|
| mindy | `cx43` | 8 / **16 GB** / 160 GB | yes |
| bumba | `cpx11` | 2 / **2 GB** / 40 GB | **no** — `ash, hil` only |

Two consequences, and the second is the one that bites this document.

**bumba cannot be recreated.** The `cpx*1` line is US-only now and `cx11`–`cx51`
are gone entirely. That is a tooling problem, handled by `prevent_destroy` in
[`tofu/`](../tofu/README.md).

**bumba cannot hold the consolidated database.** The plan of record — auth and
all databases on one key box — puts Zitadel, postgres and immich's pgvector
workload on **2 GB of RAM**. That is why immich already crashes it. The postgres
row in the table above lists immich among the databases whose primary is
"Hetzner"; on a `cpx11` that is not achievable.

So the consolidation needs one of two things, and they are not equally good:

| option | effect |
|---|---|
| **rescale bumba off `cpx11`** (`cpx22`: 2 / 4 GB / 80 GB, or `cpx32`: 4 / 8 GB / 160 GB) | solves the RAM ceiling **and** the deprecated type in one in-place change. Needs a reboot; a disk-growing rescale is irreversible. |
| databases to mindy instead | mindy has 16 GB and the volume can move — both servers are in `fsn1` and volumes attach within a location. But it puts auth and data on separate boxes, which is the split the consolidation was meant to remove. |

The rescale is the better move: it is the only one that fixes both problems, and
the deprecated type has to be dealt with eventually regardless. Size it against
immich's actual postgres footprint before picking `cpx22` over `cpx32` — 4 GB
shared with Zitadel is not obviously enough.

### Audio: 52 GB analysed 2026-09-14

`/export/audio` is not one thing. Breaking it down changed the volume sizing from
150 GB to 100 GB:

|                                        | size     | disposition                                                                         |
|----------------------------------------|----------|-------------------------------------------------------------------------------------|
| `gigs/20260618 - Dries ensemble...`    | **29 G** | one session: 19 multitrack WAV (20 G) + one Audacity project (8.4 G) -> **archive** |
| `Sounds`                               | 8.0 G    | volume                                                                              |
| `docs`                                 | 6.3 G    | volume                                                                              |
| `software` (`.zip .pkg .exe .dmg .gz`) | 5.7 G    | **re-downloadable installers — exclude**                                            |
| `testfile`                             | 2.0 G    | **delete**                                                                          |
| other `gigs` sessions                  | ~0.6 G   | volume                                                                              |

**FLAC the WAVs first.** 21.6 GB of `.wav` across the tree converts losslessly to
~11 GB, and 20 GB of that is in the one session being archived — so converting
before moving halves the copy. FLAC is already in use here (6.4 GB across 43
files), just not consistently.

**The single Audacity `.aup3` is 8.37 GB** sitting beside 20 GB of WAV from the
same performance. Audacity 3 stores audio *inside* the project, so unless it
holds edits absent from the WAVs, that performance is stored twice. If the
project is finished, archive it; if not, *File -> Compact Project* discards undo
history and unreferenced audio.

Two constraints on doing the move:

- **`gigs` and `audio-archive` are separate subvolumes**, so `mv` between them is
  a copy-and-delete, not a rename — 30 GB of I/O. Not while the raid1 balance is
  running.
- **`audio-archive` is not backed up by kopia.** It is in `btrbk.conf` (so the
  14 TB drive covers it) but `/docker-volumes/kopia/data/audio-archive` does not
  exist on mindy, so that fstab line fails silently — defect #4 from the August
  audit, still open. Moving 29 GB of irreplaceable recordings there today leaves
  them with two copies, one up to four months stale. Fix the mount first, or
  ensure the archive is covered by whatever replaces kopia.

## Does samson have room?

**Yes, with about 1.3 TiB of growth runway.**

```
samson raid1 usable (3 x 7.28 TiB / 2)   10.92 TiB
  media (primary)                         8.30 TiB
  backup of Hetzner data + versions       0.20 TiB
  ----------------------------------------------
  total                                   8.50 TiB
  free                                    2.42 TiB   (22%)

media growth before dropping below 10% free   1.33 TiB
```

The Hetzner backup is cheap: ~118 GB of data whose version history is small
because photos are append-mostly and kopia deduplicates. It is **media growth
that consumes the headroom**, at roughly 1.3 TiB before btrfs gets uncomfortable.

When that runs out, the fourth drive becomes a capacity purchase made
deliberately — not the EUR 450 emergency that was declined in September.

## Why the storage box stays (downsized), and the volume stays small

The reverse flow is what decides this. At Hetzner's EUR 0.069212/GB/month:

| volume size | holds                         | EUR/month | EUR/year |
|-------------|-------------------------------|-----------|----------|
| 150 GB      | photos + audio + documents    | **10.38** | 125      |
| 1000 GB     | the above **+ curated media** | **69.21** | **831**  |

Putting 810 GB of archival media on block storage costs **EUR 831/year** — more
than a replacement 8 TB drive, every year, forever. Block storage is priced for
live data.

So the two Hetzner services do different jobs and both are needed:

|             | Hetzner Cloud Volume                | Hetzner Storage Box         |
|-------------|-------------------------------------|-----------------------------|
| holds       | photos, audio, documents — **live** | curated media — **archive** |
| accessed by | immich, filebrowser, postgres       | kopia, write-once           |
| needs       | POSIX, low latency                  | cheap capacity              |
| size        | 150 GB                              | ~1 TB                       |

**The storage box does not go — it shrinks and changes role.** Today it holds
~900 GB of 5.5 TB, six times more than needed, and backs up data that lives at
home. Afterwards it holds the curated media archive and is sized for it.

## Why this is better than today

- **Every NFS mount disappears.** The apps sit on the same host as their data.
  The August cascade — filebrowser blocking in `stat()`, nightly kopia tree-walk
  stalls, empty exports triggering the retention hazard — all of it required NFS
  over a residential WAN.
- **Backups run in the fast direction.** Hetzner -> home is samson's *download*,
  the usable half of an ADSL line. Today kopia walks samson's tree *from* Hetzner,
  which is what produced the recurring `nfs: server not responding` stalls.
- **Provider independence improves.** Today the irreplaceable data is live at
  home with its backup at Hetzner. Afterwards it is live at Hetzner with a
  versioned backup at home and an air-gapped copy at family — three locations,
  two providers, one offline.
- **One backup mechanism at home.** Once the Hetzner copy lands on samson's
  array, the existing `btrbk` job sends it to the 14 TB drive alongside the
  media. Nothing new to build; nothing new to notice has stopped.

## The condition that makes it work

**The home copy must be versioned, not a mirror.** An `rsync --delete` from
Hetzner would propagate a deletion or a ransomware encryption to samson on the
next run, and from there to the off-site drive — three copies of the same damage.

Use **kopia with the repository on samson**: mindy and bumba become clients
pushing to it. That keeps encryption, deduplication and retention, and is nearly
the design already written in [`../samson/kopia/README.md`](../samson/kopia/README.md)
with the roles reversed.

## Sequencing

Never be down to one copy of anything:

1. Resize the Hetzner volume to 150 GB; confirm it is in the **same location** as
   the host that will use it (volumes attach only within a location, and the
   existing one is on **bumba** while immich and filebrowser run on **mindy**)
2. Restore photos/audio/documents onto it **from the storage box**, not from home
   — that copy is already inside Hetzner, so it avoids pushing 118 GB up an ADSL
   line. Then `rsync` only the delta from samson
3. Cut immich and filebrowser over by **keeping the mount paths identical** and
   swapping what is behind them, so no application config changes and the
   rollback is remounting the NFS
4. Stand up the kopia repository on samson; run it **alongside** the storage box
   until a restore has been tested from it
5. Only then: shrink the storage box to ~1 TB and repoint it at the curated media
6. Delete the NFS exports and mounts

## Open questions

- [ ] Are mindy and bumba in the same Hetzner location? (`hcloud server list`)
- [ ] Does the volume move to mindy, or do the apps move to bumba?
- [ ] Current storage box plan and the price of a ~1 TB one
- [x] `memos` — **resolved 2026-09-14.** The container was moved from bumba to
  mindy without its data and had been running against an empty database.
  Migrated: 45 notes, 39 attachments, 3 users. bumba's copy is now the orphan
  and can be dropped once verified in the UI. **Check every other service that has changed host for the same pattern** —
  an app pointed at an empty database looks identical to an app nobody has
  used lately.
- [ ] Does the curated-media set need re-reviewing? It was chosen as 57 hand-picked
  directories, with at least one overlapping pair, and anything added outside
  those exact paths is silently unprotected
