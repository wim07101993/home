# samson -- the NAS at home. Where the media array and the database dumps
# actually live, and so where they are backed up from.
#
# Every module here takes docker.samson.

# databasus -- the database backup tool, on samson. First thing in tofu on that
# host; plex is the other compose container still there.
#
# A CUTOVER. The portainer stack (id 6, project `bakup-server`) MUST be deleted
# before this is applied, or the create fails on the container name and the two
# systems fight over it daily afterwards. See the module README.
module "databasus" {
  source = "./modules/services/databasus"

  providers = {
    docker = docker.samson
  }

  # The dumps are checked from here and reported to gatus on bumba -- the token
  # crosses hosts through the graph rather than by hand. See
  # modules/services/databasus/check-backups.sh.
  gatus_token    = module.gatus.databasus_push_token
  gatus_base_url = module.gatus.external_endpoint_base_url

  # Floors are roughly half of what each database produced on 2026-09-22:
  # 675 KB, 142 MB, 111 MB, 966 KB, 806 KB. Prefixes are databasus's DISPLAY
  # names, which is why only zitadel is lower-case.
  monitored = {
    kitchenowl = { prefix = "KitchenOwl", min_bytes = 300000 }
    immich     = { prefix = "Immich", min_bytes = 70000000 }
    memos      = { prefix = "Memos", min_bytes = 55000000 }
    score      = { prefix = "Score", min_bytes = 450000 }
    zitadel    = { prefix = "zitadel", min_bytes = 400000 }
  }
}

# plex on samson. No reverse proxy, no zitadel client: Plex does its own auth
# against plex.tv and is reached on the tailnet at 32400.
#
# CUT OVER FROM A PORTAINER STACK -- delete it there first. See the module
# README; this is the same order databasus needed.
module "plex" {
  source = "./modules/services/plex"

  providers = {
    docker = docker.samson
  }
}

# samson's kopia. Snapshots the array LOCALLY, where mindy has been walking it
# over NFS-over-Tailscale -- the scanning that produced the recurring
# `nfs: server not responding` stalls and took filebrowser down on 2026-08-09.
#
# SAME repository as mindy, reached through the proxy on bumba because the
# Storage Box offers samson no authentication methods directly. Sharing it is
# what makes this cheap: ~800 GB of media and audio-archive is already stored,
# so the first snapshot dedups rather than uploading.
#
# Its own identity (`samson`), so these become new sources rather than
# continuing mindy's. History for the old `root@1da0a4624124:/data/media/...`
# sources is not lost -- it ages out under the existing retention.
#
# PREREQUISITE, host state: /docker-volumes/kopia must exist on samson. A
# missing bind source is not an error; docker creates an empty directory and
# kopia starts with no config.
#
# mindy keeps snapshotting these three paths until samson demonstrably is --
# see the module README. Removing them from mindy first leaves a window where
# nothing covers the array.
module "kopia_samson" {
  source = "./modules/services/kopia"

  providers = {
    docker = docker.samson
  }

  tailscale_ip       = var.samson_addr
  container_hostname = "samson"

  # The array is local here, so hashing is bound by CPU rather than by a
  # network walk. samson is a NAS with nothing else competing for cores.
  #
  # "4.0", not "4" -- docker normalises it and `cpus = "4"` reads back as a
  # change that FORCES REPLACEMENT, rebuilding this container on every apply.
  cpus = "4.0"

  # samson's dockerd sets these daemon-wide; omitting them plans a replacement
  # every time. See the module's var.log_opts.
  log_opts = {
    "max-file" = "3"
    "max-size" = "50m"
  }

  # MOUNTED: the whole library. SNAPSHOTTED: 48 chosen paths under it.
  #
  # That split is the point. /export/media is 8.4 TB against 4.5 TB free on the
  # Storage Box, so backing up the directory is not an option -- it would fill
  # the box and stop EVERY backup, database dumps and photos included. It was
  # briefly configured that way on 2026-09-25 and caught mid-bootstrap.
  #
  # The 48 are a deliberate choice about what is worth off-site, made before
  # this migration. They move here rather than staying on mindy because this is
  # where the data lives; mindy was reading them over NFS across the home
  # uplink, which is what produced the `nfs: server not responding` stalls.
  mounts = {
    media         = "/export/media"
    audio-archive = "/export/audio-archive"
    backups       = "/export/backups"
  }

  # MOVED to ../backrest, which is the module that outlives this one. Both read
  # the same file during the parallel period so the selection cannot drift
  # between the two systems.
  #
  # The 48 titles live in their own file, because they are a LIST. They were
  # 48 empty entries in policies.json until 2026-09-25 -- policies that said
  # nothing, existing only to be enumerated here. kopia inherits (global) with
  # or without an empty policy, so they carried no meaning and made a file
  # where every other line matters look like boilerplate.
  sources = [for p in local.samson_backup_paths : "/data/${p}"]

  # No NFS submounts to propagate here -- these are local btrfs subvolumes, so
  # nothing arrives after the container starts. The /data bind is not just
  # redundant but breaking: it is read-only, so docker cannot create the nested
  # mount targets inside it. See the module's var.bind_data_root.
  bind_data_root = false
  config_path    = "/docker-volumes/kopia"

  repository_hostname = "samson"
  repository_password = var.kopia_repository_password
  sftp_password       = module.hetzner.storage_box_sftp_password

  # Through bumba. samson cannot authenticate to the Storage Box directly --
  # it is offered no auth methods at all. See modules/services/storage-box-proxy.
  connect_host = var.bumba_addr
  connect_port = 2223

  gatus_token    = module.gatus.kopia_push_token
  gatus_base_url = module.gatus.external_endpoint_base_url
  gatus_endpoint = "backups_kopia-samson"

  # import_policies stays FALSE. mindy owns policies.json for the whole
  # repository; a second importer would delete mindy's policies on a schedule.
}

module "backrest_samson" {
  source = "./modules/services/backrest"

  providers = {
    docker = docker.samson
  }

  instance     = "samson"
  tailscale_ip = var.samson_addr
  config_path  = "/docker-volumes/backrest"

  # The array is local here, so hashing is CPU-bound rather than a network walk.
  # "4.0", not "4" -- see the module's var.cpus.
  cpus = "4.0"

  # samson's dockerd sets these daemon-wide; omitting them plans a replacement
  # on every apply. See the module's var.log_opts.
  log_opts = {
    "max-file" = "3"
    "max-size" = "50m"
  }

  # MOUNTED: the whole library. BACKED UP: the 48 chosen paths below.
  mounts = {
    media         = "/export/media"
    audio-archive = "/export/audio-archive"
    backups       = "/export/backups"
  }

  # THE SAME FILE kopia reads, with the mount root swapped. One list, so the
  # selection cannot drift between the two systems while they run in parallel --
  # which is exactly the drift that put the whole 8.4 TB library in scope twice
  # on 2026-09-25.
  paths = [for p in local.samson_backup_paths : "/backup/${p}"]

  repository_password = random_password.backrest_repository.result
  repo_path           = "restic"
  sftp_username       = module.hetzner.backrest_sftp["samson"].username
  sftp_password       = module.hetzner.backrest_sftp["samson"].password

  # Through bumba. samson cannot authenticate to the Storage Box directly.
  connect_host = var.bumba_addr
  connect_port = 2223

  gatus_token    = module.gatus.backrest_push_token
  gatus_base_url = module.gatus.external_endpoint_base_url
  gatus_endpoint = "backups_backrest-samson"

  # THE CLIENT of the sync pair. Pushes its operations up to mindy so both
  # appear in one dashboard; samson's own UI keeps working regardless.
  #
  # Plain http over the tailnet -- the handshake is signed with the identities
  # above, so the transport is not what authenticates it.
  sync_identity = var.backrest_identity_samson
  sync_known_hosts = var.backrest_identity_mindy == null ? [] : [{
    instance_id  = "mindy"
    keyid        = var.backrest_identity_mindy.keyid
    instance_url = "http://${var.mindy_addr}:9898"
    scopes       = ["*"]
  }]
}

# --- values ---------------------------------------------------------------

locals {
  # What samson backs up, RELATIVE TO THE MOUNT ROOT -- `media/live`, not
  # `/data/media/live`. Read by both kopia and backrest while they run in
  # parallel, each prepending its own root below.
  #
  # RELATIVE because the root differs per tool: kopia mounts at /data, backrest
  # at /backup. Encoding one of them here meant the other had to rewrite the
  # prefix, and the obvious way to do that is a trap --
  #
  #   replace(line, "/data/", "/backup/")
  #
  # OpenTofu treats a SLASH-WRAPPED substring as a REGEX, so that pattern is
  # `data` and the result is `//backup//media/live`. Fifty paths that do not
  # exist, and restic would have backed up nothing while reporting success.
  # Caught in a render check on 2026-09-26.
  #
  # ONE LIST for both systems. The selection drifting between them is exactly
  # how the whole 8.4 TB library came into scope twice on 2026-09-25.
  #
  # THE 8.4 TB IS THE REASON THIS IS A LIST AT ALL. /export/media does not fit
  # in a 5.5 TB Storage Box, so the directory is mounted but never backed up
  # wholesale -- only these paths. They are a deliberate choice about what is
  # worth off-site, not a consequence of how the folders are arranged.
  #
  # Was ./modules/services/backrest/samson-media-sources.txt until 2026-09-27.
  # Inlined because a 48-line data file next to 1000 lines of config read like
  # boilerplate, and the paths are config like everything else here.
  samson_backup_paths = concat(
    ["audio-archive", "backups"],
    [
      "media/live",
      "media/movies/animated/1990-1999/The Lion King (1994)",
      "media/movies/animated/1990-1999/The Lion King II Simbas Pride (1998)",
      "media/movies/animated/2000-2009/Bob De Bouwer - Hoe Bob Een Bouwer Werd (2008)",
      "media/movies/animated/2000-2009/Bob de Bouwer - Molly geeft eerste hulp (2004)",
      "media/movies/animated/2000-2009/Bob de Bouwer - Race naar de finish (2008)",
      "media/movies/animated/2000-2009/Bob de Bouwer Werk in Uitvoering - Bob's Grote Plan (2005)",
      "media/movies/animated/2000-2009/Bob de Bouwer werk in uitvoering- Ridder Muck (2007)",
      "media/movies/animated/2000-2009/Bob de bouwer - Leve het wilde westen (2007)",
      "media/movies/animated/2000-2009/Bob de bouwer - Wendy's drukke dag (2004)",
      "media/movies/animated/2000-2009/Bob de bouwer Werk in uitvoering - Crossen met Scrambler (2006)",
      "media/movies/animated/2000-2009/Bob de bouwer en de ridders van Makelot (2004)",
      "media/movies/animated/2000-2009/Bob de bouwer werk in uitvoering - De oogst van Spud (2006)",
      "media/movies/animated/2000-2009/Bob de bouwer werk in uitvoering ‐ Packers eerste dag (2008)",
      "media/movies/animated/2000-2009/The Lion King 1½ (2004)",
      "media/series/animated/Alfred J. Kwak",
      "media/series/animated/Avatar - The Last Airbender (2005)/Season 01 - Water (2005)",
      "media/series/animated/Buurman & Buurman (1976)",
      "media/series/animated/Danny Phantom (2004)",
      "media/series/animated/David de kabouter",
      "media/series/animated/De fabeltjeskrant",
      "media/series/animated/De smufen",
      "media/series/animated/Dragonball (1986)",
      "media/series/animated/Er Was Eens ... De aarde",
      "media/series/animated/Er Was Eens ... De mens",
      "media/series/animated/Er Was Eens ... De ruimte",
      "media/series/animated/Er was eens ... Het Leven",
      "media/series/animated/Lucky Luke",
      "media/series/animated/Maya De Bij",
      "media/series/animated/Nick Bruna's Nijntje (1984)",
      "media/series/animated/Nijntje En Vriendjes (2003)",
      "media/series/animated/Noahs Island (1997)",
      "media/series/animated/Plonsters (1987)",
      "media/series/animated/Plonsters (1987)/Season 01",
      "media/series/animated/The Animals of Farthing Wood (1993)",
      "media/series/animated/Tiktak",
      "media/series/animated/Tiktak (2019-2020)",
      "media/series/live-action/'Allo 'Allo! (1982)",
      "media/series/live-action/Bumba",
      "media/series/live-action/Dag Sinterklaas",
      "media/series/live-action/Doctor Who (1963)",
      "media/series/live-action/Drake & Josh (2004)",
      "media/series/live-action/Kabouter Plop",
      "media/series/live-action/Kulderzipken",
      "media/series/live-action/Mythbusters (2003)",
      "media/series/live-action/Spring",
      "media/series/live-action/Teletubbies nl (1997)",
      "media/series/live-action/W817",
    ],
  )
}

# --- inputs ---------------------------------------------------------------

variable "samson_addr" {
  type        = string
  description = "samson's TAILNET address. Reached as root over SSH for the docker provider, like the other two hosts."
}

# samson's half of the sync pair, so its backup progress shows up in mindy's
# dashboard as well as its own. null disables sync on both sides.
#
# Generated by ./backrest-identity.sh. The reasoning for why these are supplied
# rather than generated by tofu is on backrest_identity_mindy in mindy.tf, and at
# length in that script.
variable "backrest_identity_samson" {
  type = object({
    keyid = string
    priv  = string
    pub   = string
  })
  default   = null
  sensitive = true
}

# --- outputs --------------------------------------------------------------

output "kopia_samson_password" {
  value     = module.kopia_samson.server_password
  sensitive = true
}

output "backrest_samson_password" {
  value     = module.backrest_samson.ui_password
  sensitive = true
}
