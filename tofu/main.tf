# One root module, several child modules. One state, one init, one apply --
# the directories are for reading, not for isolation.
#
# Providers are configured once, in providers.tf, and inherited. No child
# declares a provider block, so there is exactly one place the Hetzner token,
# the postgres superuser password and the docker endpoints are wired in.
#
# Service modules take their docker provider explicitly rather than inheriting
# a default. There is no default on purpose:
# `docker.bumba` and `docker.mindy` point at different daemons, and an apply
# against the wrong one recreates the wrong front door.

# The photo library's location, used by the service that SERVES it and the one
# that BACKS IT UP. One value, because the failure mode when they disagree is
# silent: immich reading the new copy while kopia faithfully snapshots the old
# one, both looking healthy.
locals {
  photos_path = "/mnt/rafiki/photos"

  # The document shares, moved off samson's NFS on 2026-09-18. ~639 MB in total
  # -- `sara` and `gezin-officieel-archive` are empty and moved anyway, so the
  # set is complete and nothing is left half-migrated.
  #
  # `audio` (55.4 GB) and `audio-archive` are NOT here: rafiki has ~27 GB free
  # after photos. docs/data-architecture.md has a plan for that -- FLAC the
  # WAVs and archive the 29 GB session first -- and it needs doing before audio
  # can follow.
  documents_path = "/mnt/rafiki/documents"

  # The audio share, moved off samson on 2026-09-18 after `gigs`, part of `docs`
  # and part of `software` were archived to `audio-archive` -- which STAYS on
  # samson, by intent. ~19.5 GB moved; 32 GB stayed behind.
  audio_path = "/mnt/rafiki/audio"

  # What samson backs up, RELATIVE TO THE MOUNT ROOT. Read by both kopia and
  # backrest while they run in parallel, each prepending its own root -- see
  # modules/services/backrest/samson-media-sources.txt for why the file holds
  # neither.
  #
  # ONE LIST. The selection drifting between the two systems is exactly how the
  # whole 8.4 TB library came into scope twice on 2026-09-25.
  samson_backup_paths = concat(
    ["audio-archive", "backups"],
    [
      for line in split("\n", trimspace(file("${path.module}/modules/services/backrest/samson-media-sources.txt"))) :
      trimspace(line) if trimspace(line) != "" && !startswith(trimspace(line), "#")
    ],
  )

  document_shares = [
    "gezin-officieel",
    "gezin-officieel-archive",
    "sara",
    "wim",
  ]
}

module "hetzner" {
  source = "./modules/hetzner"

}

# SMTP credentials for outbound alerts. Credentials only -- the sending domain
# is deliberately unmanaged, see the module.
module "mailgun" {
  source = "./modules/mailgun"
}

# The traefik networks, one per host. Extracted from the reverse-proxy module so
# that routing can be sliced per service without a dependency cycle -- see
# modules/network.
module "network_bumba" {
  source = "./modules/network"

  providers = { docker = docker.bumba }

  name = "reverse-proxy_reverse-proxy-network"
  labels = {
    "com.docker.compose.config-hash" = "269096a0575268b819c342ef4a1d6d6c8240ce7cd8ddfb507530a7587d85e957"
    "com.docker.compose.network"     = "reverse-proxy-network"
    "com.docker.compose.project"     = "reverse-proxy"
    "com.docker.compose.version"     = ""
  }
}

module "network_mindy" {
  source = "./modules/network"

  providers = { docker = docker.mindy }

  name = "traefik_traefik-network"
  labels = {
    "com.docker.compose.config-hash" = "a28de9114d611e880f6424720a2fbf6580fde482deabb368bd099ee6e96b8c6c"
    "com.docker.compose.network"     = "traefik-network"
    "com.docker.compose.project"     = "traefik"
    "com.docker.compose.version"     = ""
  }
}

# bumba's traefik. A cutover, not an adoption -- see the module README.
# mindy's traefik stays on compose for now.
module "reverse_proxy_bumba" {
  source = "./modules/services/reverse-proxy"

  providers = {
    docker = docker.bumba
  }

  host           = "bumba"
  container_name = "reverse-proxy"
  network_name   = module.network_bumba.name
  image_tag      = "v3.7.10"
  dashboard_host = "wvl.app"

  routing = [
    module.zitadel_server.traefik,
    module.gatus.traefik,
  ]

}

# mindy's traefik. Same shape, different host. Cutover, not adoption.
module "reverse_proxy_mindy" {
  source = "./modules/services/reverse-proxy"

  providers = {
    docker = docker.mindy
  }

  host           = "mindy"
  container_name = "traefik"
  network_name   = module.network_mindy.name
  image_tag      = "v3.7.13"
  dashboard_host = "traefik.wvl.app"

  routing = [
    module.file_browser.traefik,
    module.immich.traefik,
    module.homepage.traefik,
    module.it_tools.traefik,
    module.kitchen_owl.traefik,
    module.memo.traefik,
    module.score.traefik,
  ]

  # From `docker network inspect traefik_traefik-network` on mindy,
  # 2026-09-17. Note the project is `traefik` and the hash is mindy's own --
  # these were briefly hardcoded to bumba's values, which would have stamped
  # this network with the wrong stack's identity.
}


# auth.wvl.app's CONTAINERS. A cutover from the portainer git stack -- see the
# module. `zitadel_server` is the deployment; `zitadel` below is its contents.
#
# depends_on the NETWORK, not the proxy. It used to be module.reverse_proxy_bumba
# because that module created the network; now routing flows the other way --
# the proxy consumes this module's `traefik` output -- and naming the proxy here
# is a cycle:
#
#   Cycle: module.zitadel_server (expand), module.zitadel_server.output.traefik,
#          module.reverse_proxy_bumba.var.routing, ...
#
# depends_on because both containers attach to networks these modules own, and
# because zitadel cannot start before its database container exists.
module "zitadel_server" {
  source = "./modules/services/zitadel"

  # A VERTICAL SLICE: zitadel owns its own database and roles, on bumba.
  providers = {
    docker     = docker.bumba
    postgresql = postgresql
  }

  traefik_network = module.network_bumba.name
  db_network      = module.postgres_bumba.network_name

  depends_on = [module.postgres_bumba, module.network_bumba]
}

# Projects, roles and OIDC applications. A REBUILD, not an adoption -- orgs
# and users are deliberately untouched. modules/zitadel/orgs.tf says why.
#
# depends_on because the zitadel PROVIDER talks to auth.wvl.app, which is served
# by bumba's traefik. Nothing else in the graph expresses that, so tofu is free
# to replace traefik and call the zitadel API at the same moment.
#
# It did, on 2026-09-17:
#
#   module.reverse_proxy_bumba.docker_container.this: Destroying...
#   module.zitadel.zitadel_project.status: Creating...
#   Error: dial tcp 5.75.247.152:443: connect: connection refused
#
# Traefik was down for ONE SECOND and the apply failed half-finished. Changing
# dynamic.yml replaces the container, so this is a hazard on any routing change,
# not a one-off.
module "zitadel" {
  source = "./modules/zitadel"

  # Zitadel's own outbound mail credential. Created by tofu, so there is no
  # SMTP password to type and rotating it is an apply.
  smtp_user     = module.mailgun.auth_smtp_username
  smtp_password = module.mailgun.auth_smtp_password

  depends_on = [module.reverse_proxy_bumba, module.zitadel_server]
}

# Assembled from the instance-level module and each vertical slice. The cutover
# needs every client id in one place even though the resources now live with the
# service that uses them.
output "zitadel_apps" {
  description = "New client ids and secrets for the cutover. `tofu output -json zitadel_apps`."
  sensitive   = true
  value = merge(
    module.score.zitadel_apps,
    {
      "home/home assistant"        = module.home_assistant.zitadel_app
      "memo/memo"                  = module.memo.zitadel_app
      "keuken/kitchen owl web-app" = module.kitchen_owl.zitadel_app
      "status/gatus"               = module.gatus.zitadel_app
      "photos/immich"              = module.immich.zitadel_app
      "drive/drive"                = module.file_browser.zitadel_app
    },
  )
}

output "zitadel_project_ids" {
  value = {
    "home"   = module.home_assistant.zitadel_project_id
    "memo"   = module.memo.zitadel_project_id
    "keuken" = module.kitchen_owl.zitadel_project_id
    "status" = module.gatus.zitadel_project_id
    "photos" = module.immich.zitadel_project_id
    "drive"  = module.file_browser.zitadel_project_id
    "Score"  = module.score.zitadel_project_id
  }
}

# bumba's postgres. The container holding zitadel's database, score's, and --
# normally -- this state. See the module README before touching it.
module "postgres_bumba" {
  source = "./modules/services/postgres"

  providers = {
    docker = docker.bumba
  }

  container_name = "database-db-1"
  network_name   = "database_db-network"

  # From `docker network inspect database_db-network` on bumba, 2026-09-17.
  network_labels = {
    "com.docker.compose.config-hash" = "6723d56766a425ef676f8dc75eeff5a7178b8f4fb7298a50613bcf948efd9d78"
    "com.docker.compose.network"     = "db-network"
    "com.docker.compose.project"     = "database"
    "com.docker.compose.version"     = ""
  }
}

# it-tools.wvl.app. No database, no OIDC, no secrets -- the cheapest container
# to move, and therefore the one to prove the pattern on.
module "it_tools" {
  source = "./modules/services/it-tools"

  providers = {
    docker = docker.mindy
  }

  network_name = module.network_mindy.name
}

# mindy's postgres. memos and filebrowser depend on it. Unlike bumba's, it
# holds no tofu state, so no round-trip is needed.
module "postgres_mindy" {
  source = "./modules/services/postgres"

  providers = {
    docker = docker.mindy
  }

  container_name = "db"
  network_name   = "db_db-network"

  # From `docker network inspect db_db-network` on mindy, 2026-09-17. The
  # project is `db` here and `database` on bumba -- reproducing bumba's would
  # stamp this network with the wrong stack's identity.
  network_labels = {
    "com.docker.compose.config-hash" = "c84a1ab54cb8990da8545ea8c010f473d33fe3a55851f06124cd5831ae855a9b"
    "com.docker.compose.network"     = "db-network"
    "com.docker.compose.project"     = "db"
    "com.docker.compose.version"     = ""
  }
}

# memo.wvl.app. First container with a database dependency and a secret.
module "memo" {
  source = "./modules/services/memo"

  # A VERTICAL SLICE -- memo owns its database, role and zitadel client. Three
  # providers: docker and postgresql are per-host and passed explicitly, zitadel
  # is a single instance.
  providers = {
    docker     = docker.mindy
    postgresql = postgresql.mindy
    zitadel    = zitadel
  }

  traefik_network = module.network_mindy.name
  db_network      = module.postgres_mindy.network_name

  org_id = module.zitadel.org_home_id

  # The db_network reference orders this after the NETWORK, not after the
  # database container -- so tofu created both in parallel on 2026-09-17 and
  # memos' first connection attempt raced postgres' startup. `unless-stopped`
  # covered it, but relying on a restart policy for ordering is luck.
  depends_on = [module.postgres_mindy]
}

# drive.wvl.app. The one with rslave-propagated NFS mounts under it.
module "file_browser" {
  source = "./modules/services/file-browser"

  providers = {
    docker  = docker.mindy
    zitadel = zitadel
  }

  audio_path      = local.audio_path
  documents_path  = local.documents_path
  document_shares = local.document_shares

  # Display names are a human choice, so they are listed rather than derived.
  # The module has a precondition asserting every entry in local.document_shares
  # appears here -- add a share to that list without adding it here and the plan
  # fails, instead of the directory quietly not existing in the UI.
  #
  # default_enabled = true means a newly created user is granted the source.
  # The two personal shares stay false: they are granted by hand, per person.
  sources = [
    { path = "/files/gezin-officieel", name = "Gezin officieel", default_enabled = true },
    { path = "/files/gezin-officieel-archive", name = "Gezin officieel archive", default_enabled = true },
    { path = "/files/audio", name = "Audio", default_enabled = true },
    { path = "/files/audio-archive", name = "Audio archive", default_enabled = true },
    { path = "/files/wim", name = "Wim privé", default_enabled = false },
    { path = "/files/sara", name = "Sara prive", default_enabled = false },
  ]

  # Still the home-old project's app. See the variable's comment.
  oidc_client_id = "367153386023354372"

  traefik_network = module.network_mindy.name
  db_network      = module.postgres_mindy.network_name

  depends_on = [module.postgres_mindy]

  org_id = module.zitadel.org_home_id
}

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

# Home Assistant and the Matter server on plop.
#
# CUT OVER FROM A PORTAINER STACK, and this one is NOT a plain stack delete:
# the Matter fabric is in an anonymous docker volume that the delete can
# destroy. Read the module README first.
#
# The zitadel client for Home Assistant is in ../zitadel rather than here --
# it predates this module, and moving it is a separate `moved` block.
module "home_assistant" {
  source = "./modules/services/home-assistant"

  providers = {
    docker  = docker.plop
    zitadel = zitadel
  }

  org_id       = module.zitadel.org_home_id
  tailscale_ip = var.plop_addr
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

# homepage.wvl.app -- the dashboard.
module "homepage" {
  source = "./modules/services/homepage"

  providers = {
    docker = docker.mindy
  }

  traefik_network = module.network_mindy.name
}

# score.wvl.app / partituren.wvl.app / score-api.wvl.app
#
# Moved from bumba to mindy AND cut over to the rebuilt zitadel apps in one
# change, because the config files had to be rewritten either way -- the
# connection string changes with the host. Doing it in two passes would have
# meant hand-editing them once and regenerating them later.
module "score" {
  source = "./modules/services/score"

  providers = {
    docker     = docker.mindy
    postgresql = postgresql.mindy
    zitadel    = zitadel
  }

  traefik_network = module.network_mindy.name
  db_network      = module.postgres_mindy.network_name

  org_id = module.zitadel.org_home_id

  depends_on = [module.postgres_mindy]
}

# The estate's only off-site backup. A cutover from the compose stack in
# mindy/kopia/ -- delete that stack before applying, or it redeploys and fights
# tofu for the same container.
#
# No depends_on: it reaches samson over NFS mounts in mindy's fstab and the
# Storage Box over SFTP, neither of which tofu owns.
module "kopia" {
  source = "./modules/services/kopia"

  providers = {
    docker = docker.mindy
  }

  tailscale_ip       = var.mindy_addr
  container_hostname = "mindy"

  # Keys are container paths under /data, and they ARE the snapshot identity --
  # `photos` because that is what it was when it came over NFS from samson, not
  # because it reads well. See the module's var.sources.
  #
  # audio-archive, backups and media are absent on purpose: they stay on samson
  # and arrive as NFS submounts through the /data bind. They move to samson's
  # own kopia instance, not here.
  mounts = merge(
    {
      photos = local.photos_path
      audio  = local.audio_path
    },
    { for share in local.document_shares : share => "${local.documents_path}/${share}" },
  )

  # `sources` unset: nothing to exclude, so kopia backs up every mount.

  repository_password = var.kopia_repository_password
  sftp_password       = module.hetzner.storage_box_sftp_password

  # The heartbeat. kopia reports snapshot freshness to gatus on bumba, which is
  # the only thing that would have caught either of the two outages this
  # service has had -- five weeks crash-looping, and four days cleanly stopped.
  gatus_token    = module.gatus.kopia_push_token
  gatus_base_url = module.gatus.external_endpoint_base_url
  gatus_endpoint = "backups_kopia-mindy"

  # mindy is the ONE instance that writes policies.json into the repository.
  # See the module's var.import_policies -- a second importer would delete
  # this one's policies on a schedule.
  import_policies = true
}

# photos.wvl.app -- four containers, an NFS library from samson, and immich's
# own pgvector postgres.
module "immich" {
  source = "./modules/services/immich"

  providers = {
    docker  = docker.mindy
    zitadel = zitadel

    # immich's OWN cluster on mindy:5434, NOT postgresql.mindy. The alias is
    # the only thing distinguishing them, and pointing this at the shared
    # instance would create the role in the wrong database.
    postgresql = postgresql.immich
  }

  library_path    = local.photos_path
  traefik_network = module.network_mindy.name

  org_id = module.zitadel.org_home_id

  superuser_password = var.immich_pg_superuser_password
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

# --- backrest: replacing kopia --------------------------------------------
#
# Running in PARALLEL with both kopia instances above, deliberately. The repo
# formats are unrelated, so this is a fresh upload rather than a conversion, and
# a backup migration is not the place to trust a new tool before it has proven
# it can read back what it wrote.
#
# SPACE. The Storage Box is 5.5 TB with 4.6 TB available as of 2026-09-24. The
# two restic repositories duplicate roughly what kopia already holds -- samson's
# ~800 GB of selected media plus mindy's photos, audio and documents -- so the
# parallel period costs about another 0.9 TB and lands near 3.7 TB free, before
# the 14 Storage Box snapshots pin anything. Comfortable, and the number to
# watch: modules/hetzner/storage-box.tf explains why `available` falling faster
# than the daily backup size means snapshots rather than backups.
#
# kopia comes out once these two have a full retention window and one restore
# has actually been tested from the UI.
# Encrypts BOTH restic repositories. GENERATED, unlike the kopia equivalent it
# replaces.
#
# It can be generated because it configures nothing at plan time -- it is a
# string written into an uploaded config.json. That is the distinction immich's
# superuser password could not clear (see providers.tf): a provider must be
# CONFIGURED before anything is created, so a value that does not exist yet
# cannot authenticate one. Nothing here authenticates with this.
#
# ONE value for both hosts. Their repositories are separated to confine the
# Storage Box DELETE credential -- see modules/hetzner/storage-box.tf -- not to
# compartmentalise the encryption, and two irreplaceable secrets instead of one
# is a worse trade in the only scenario either matters.
#
# prevent_destroy IS NOT OPTIONAL HERE. This password has no reset path: a
# `-replace` on it, or any change to `keepers`, regenerates the value, the next
# apply writes a new config.json, and restic can no longer open either
# repository. The old value is gone from state with no copy anywhere. That is a
# different class of accident from the Storage Box passwords, which tofu also
# generates precisely because Hetzner can reset them.
#
# Read it out and keep a vault copy -- bw-seed.sh does this for you:
#
#   tofu output -raw backrest_repository_password
resource "random_password" "backrest_repository" {
  length = 32

  # No punctuation. The value is interpolated into JSON and read back by restic
  # through env; nothing here needs the extra entropy of characters that have to
  # survive three layers of quoting.
  special = false

  lifecycle {
    prevent_destroy = true
  }
}

module "backrest_mindy" {
  source = "./modules/services/backrest"

  providers = {
    docker = docker.mindy
  }

  instance     = "mindy"
  tailscale_ip = var.mindy_addr

  # The same data kopia backs up here, at /backup instead of /data -- see the
  # module's var.mounts for why that path moved.
  #
  # audio-archive, backups and media are absent on purpose: they live on samson
  # and are backed up there.
  mounts = merge(
    {
      photos = local.photos_path
      audio  = local.audio_path
    },
    { for share in local.document_shares : share => "${local.documents_path}/${share}" },
  )

  # `paths` unset: nothing to exclude, so every mount is backed up.

  repository_password = random_password.backrest_repository.result
  repo_path           = "restic"
  sftp_username       = module.hetzner.backrest_sftp["mindy"].username
  sftp_password       = module.hetzner.backrest_sftp["mindy"].password

  gatus_token    = module.gatus.backrest_push_token
  gatus_base_url = module.gatus.external_endpoint_base_url
  gatus_endpoint = "backups_backrest-mindy"
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
}

# The hop that lets samson and plop reach the Storage Box at all.
#
# On bumba because bumba is in Hetzner and is already a single point of failure
# -- it holds this layer's state and the monitoring -- so routing through it
# adds no new one. mindy would have worked equally well technically, and was
# rejected so the machine taking snapshots is not also the one every other host
# depends on to store them.
module "storage_box_proxy" {
  source = "./modules/services/storage-box-proxy"

  providers = {
    docker = docker.bumba
  }

  target_host  = module.hetzner.storage_box_host
  tailscale_ip = var.bumba_addr
}

# keuken.wvl.app. Moved onto the shared postgres, off its own postgres:15.
module "kitchen_owl" {
  source = "./modules/services/kitchen-owl"

  providers = {
    docker     = docker.mindy
    postgresql = postgresql.mindy
    zitadel    = zitadel
  }

  traefik_network = module.network_mindy.name
  db_network      = module.postgres_mindy.network_name

  org_id = module.zitadel.org_home_id

  depends_on = [module.postgres_mindy]
}

# status.wvl.app -- service monitoring, on bumba. The first service here that
# is created rather than migrated.
#
# Was uptime-kuma. Swapped for gatus because uptime-kuma's monitors live in a
# SQLite database behind a UI: they cannot be expressed here, reviewed in a
# diff, or restored from this repo. It ran for a week with zero monitors
# configured and nothing said so -- which is the same class of silent failure
# this service exists to catch.
module "gatus" {
  source = "./modules/services/gatus"

  providers = {
    docker  = docker.bumba
    zitadel = zitadel
  }

  traefik_network = module.network_bumba.name
  tailscale_ip    = var.bumba_addr

  org_id = module.zitadel.org_home_id

  # Created by tofu rather than typed in: modules/mailgun mints this credential
  # and the value never leaves the graph.
  smtp_username = module.mailgun.gatus_smtp_username
  smtp_password = module.mailgun.gatus_smtp_password
}

# For wiring kopia's post-snapshot push. The token is the only credential that
# can report a backup as successful, so it is sensitive:
#
#   tofu output -raw gatus_kopia_push_token
# drive.wvl.app's admin login. Generated, and written back into filebrowser on
# every container start -- see modules/services/file-browser/README.md.
#
#   tofu output -raw filebrowser_admin_password
output "filebrowser_admin_password" {
  value     = module.file_browser.admin_password
  sensitive = true
}

# Generated, and unreadable anywhere else -- the Cloud API never returns it.
#
#   tofu output -raw storage_box_password
output "storage_box_id" {
  value = module.hetzner.storage_box_id
}

output "storage_box_password" {
  value     = module.hetzner.storage_box_password
  sensitive = true
}

output "gatus_kopia_push_token" {
  description = "Bearer token for kopia's heartbeat push to gatus."
  sensitive   = true
  value       = module.gatus.kopia_push_token
}

# The kopia web UI logins, one per instance. Username is `wim` on both --
# var.server_username in the module.
#
# These became tofu-generated on 2026-09-24, when the password stopped being a
# hand-made file on the host. That silently invalidated whatever was in the
# browser's password manager, and without these outputs there was no way to
# find the new one short of reading state.
#
#   tofu output -raw kopia_mindy_password
#   tofu output -raw kopia_samson_password
output "kopia_mindy_password" {
  value     = module.kopia.server_password
  sensitive = true
}

output "kopia_samson_password" {
  value     = module.kopia_samson.server_password
  sensitive = true
}

# The restic repository password. GENERATED, so this output is the ONLY way to
# read it -- and it must end up somewhere that is not tofu state, because state
# is encrypted with the state passphrase and these backups are what you reach
# for when something has gone badly wrong.
#
#   tofu output -raw backrest_repository_password
output "backrest_repository_password" {
  value     = random_password.backrest_repository.result
  sensitive = true
}

# Backrest UI credentials, per host. Username is `wim` on both.
#
#   tofu output -raw backrest_mindy_password
#   tofu output -raw backrest_samson_password
output "backrest_mindy_password" {
  value     = module.backrest_mindy.ui_password
  sensitive = true
}

output "backrest_samson_password" {
  value     = module.backrest_samson.ui_password
  sensitive = true
}

output "backrest_urls" {
  value = {
    mindy  = module.backrest_mindy.url
    samson = module.backrest_samson.url
  }
}

output "gatus_kopia_push_url" {
  value = module.gatus.kopia_push_url
}

# --- vertical slicing, 2026-09-22 -----------------------------------------
#
# memo's database and zitadel client moved out of the shared modules and into
# the service that uses them. Every one of these is a RENAME: without them tofu
# sees six resources disappear and six appear, and plans to DROP a database and
# DELETE an OIDC client whose id memos stores as its usernames.
#
# Remove them once applied -- see the note where the previous batch was deleted.
moved {
  from = module.databases.random_password.memos
  to   = module.memo.random_password.db
}

moved {
  from = module.databases.postgresql_role.memos
  to   = module.memo.postgresql_role.this
}

moved {
  from = module.databases.postgresql_database.memos
  to   = module.memo.postgresql_database.this
}

moved {
  from = module.zitadel.zitadel_project.memo
  to   = module.memo.zitadel_project.this
}

moved {
  from = module.zitadel.zitadel_project_role.memo_family
  to   = module.memo.zitadel_project_role.family
}

moved {
  from = module.zitadel.zitadel_application_oidc.memo
  to   = module.memo.zitadel_application_oidc.this
}

moved {
  from = module.databases.random_password.kitchenowl
  to   = module.kitchen_owl.random_password.db
}

moved {
  from = module.databases.postgresql_role.kitchenowl
  to   = module.kitchen_owl.postgresql_role.this
}

moved {
  from = module.databases.postgresql_database.kitchenowl
  to   = module.kitchen_owl.postgresql_database.this
}

moved {
  from = module.zitadel.zitadel_project.keuken
  to   = module.kitchen_owl.zitadel_project.this
}

moved {
  from = module.zitadel.zitadel_project_role.keuken_family
  to   = module.kitchen_owl.zitadel_project_role.family
}

moved {
  from = module.zitadel.zitadel_application_oidc.kitchen_owl_web_app
  to   = module.kitchen_owl.zitadel_application_oidc.this
}

moved {
  from = module.databases.random_password.score_api
  to   = module.score.random_password.db
}

moved {
  from = module.databases.postgresql_role.score_api
  to   = module.score.postgresql_role.this
}

moved {
  from = module.databases.postgresql_database.score
  to   = module.score.postgresql_database.this
}

moved {
  from = module.zitadel.zitadel_project.score
  to   = module.score.zitadel_project.this
}

moved {
  from = module.zitadel.zitadel_project_role.score_editor
  to   = module.score.zitadel_project_role.editor
}

moved {
  from = module.zitadel.zitadel_project_role.score_viewer
  to   = module.score.zitadel_project_role.viewer
}

moved {
  from = module.zitadel.zitadel_application_api.score_api
  to   = module.score.zitadel_application_api.api
}

moved {
  from = module.zitadel.zitadel_application_oidc.score_web_app
  to   = module.score.zitadel_application_oidc.web
}

moved {
  from = module.zitadel.zitadel_project.status
  to   = module.gatus.zitadel_project.this
}

moved {
  from = module.zitadel.zitadel_project_role.status_admin
  to   = module.gatus.zitadel_project_role.admin
}

moved {
  from = module.zitadel.zitadel_application_oidc.gatus
  to   = module.gatus.zitadel_application_oidc.this
}

moved {
  from = module.zitadel.zitadel_project.photos
  to   = module.immich.zitadel_project.this
}

moved {
  from = module.zitadel.zitadel_project_role.photos_family
  to   = module.immich.zitadel_project_role.family
}

moved {
  from = module.zitadel.zitadel_application_oidc.immich
  to   = module.immich.zitadel_application_oidc.this
}

moved {
  from = module.zitadel.zitadel_project.drive
  to   = module.file_browser.zitadel_project.this
}

moved {
  from = module.zitadel.zitadel_project_role.drive_family
  to   = module.file_browser.zitadel_project_role.family
}

moved {
  from = module.zitadel.zitadel_application_oidc.drive
  to   = module.file_browser.zitadel_application_oidc.this
}

moved {
  from = module.databases.random_password.zitadel_user
  to   = module.zitadel_server.random_password.db_user
}

moved {
  from = module.databases.postgresql_role.zitadel_user
  to   = module.zitadel_server.postgresql_role.user
}

moved {
  from = module.databases.random_password.zitadel_root
  to   = module.zitadel_server.random_password.db_root
}

moved {
  from = module.databases.postgresql_role.zitadel_root
  to   = module.zitadel_server.postgresql_role.root
}

moved {
  from = module.databases.postgresql_database.zitadel
  to   = module.zitadel_server.postgresql_database.this
}

moved {
  from = module.reverse_proxy_bumba.docker_network.this
  to   = module.network_bumba.docker_network.this
}

moved {
  from = module.reverse_proxy_mindy.docker_network.this
  to   = module.network_mindy.docker_network.this
}

# Home assistant's zitadel client joined its service module on 2026-09-23 --
# the last project that was still in modules/zitadel. Moves, not recreates:
# a recreate would mint a new client id and secret and lock everyone out of
# Home Assistant until the config caught up.
moved {
  from = module.zitadel.zitadel_project.home
  to   = module.home_assistant.zitadel_project.this
}

moved {
  from = module.zitadel.zitadel_project_role.home_family
  to   = module.home_assistant.zitadel_project_role.family
}

moved {
  from = module.zitadel.zitadel_application_oidc.home_assistant
  to   = module.home_assistant.zitadel_application_oidc.this
}
