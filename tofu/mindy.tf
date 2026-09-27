# mindy -- cx43 in fsn1. The workhorse: most services, the shared postgres, the
# photo library and its own backups.
#
# Every module here takes docker.mindy.

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

  # No db_network and no depends_on: filebrowser never used postgres. See the
  # networks_advanced note in the module.

  org_id = module.zitadel.org_home_id
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

  # THE HOST of the sync pair -- the dashboard you actually open. samson pushes
  # its operations here, so this one shows both.
  #
  # No permissions on the client entry: the grant lives on samson's known-host
  # entry, because that is the side doing the pushing. See the module's
  # var.sync_authorized_clients.
  sync_identity = var.backrest_identity_mindy
  sync_authorized_clients = var.backrest_identity_samson == null ? [] : [{
    instance_id = "samson"
    keyid       = var.backrest_identity_samson.keyid
  }]
}

# --- values ---------------------------------------------------------------

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

  document_shares = [
    "gezin-officieel",
    "gezin-officieel-archive",
    "sara",
    "wim",
  ]
}

# --- inputs ---------------------------------------------------------------

variable "mindy_addr" {
  type        = string
  description = "mindy's TAILNET address."
}

variable "pg_superuser_password_mindy" {
  type        = string
  sensitive   = true
  description = "postgres superuser password on MINDY, from /docker-volumes/db/db_password.txt there. Different file and different value from bumba's."
}

variable "immich_pg_superuser_password" {
  type      = string
  sensitive = true

  description = <<-EOT
    postgres superuser password on IMMICH'S OWN postgres (mindy:5434), a
    different cluster from the shared one above.

    Supplied rather than generated: it configures the postgresql.immich
    provider, and a provider is configured at PLAN time, where a generated
    value is still unknown. Tried on 2026-09-23 and the plan failed with
    `password authentication failed for user "postgres"`.

    Unlike the other two, this one is ENFORCED. The container re-applies it on
    every start -- modules/services/immich/assert-superuser-password.sh -- so
    changing it here and applying is the whole rotation. No manual ALTER.
  EOT
}

# The two ed25519 sync identities, so samson's backup progress shows up in
# mindy's dashboard as well as its own.
#
# OPTIONAL: null on either side disables sync and each host keeps its own
# dashboard, which is how both ran until 2026-09-27. Nothing else degrades --
# gatus is the monitoring path either way, and it has no dependency between the
# two hosts.
#
# Generate them with ./backrest-identity.sh. SUPPLIED because Backrest generates
# its own identity when the config omits one and then writes it back into
# config.json, which this estate keeps in the container layer -- so a generated
# identity would be discarded on every apply and the pairing would break each
# time. That script explains it at length.
variable "backrest_identity_mindy" {
  type = object({
    keyid = string
    priv  = string
    pub   = string
  })
  default   = null
  sensitive = true
}

# --- outputs --------------------------------------------------------------

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

# Backrest UI credentials, per host. Username is `wim` on both.
#
#   tofu output -raw backrest_mindy_password
#   tofu output -raw backrest_samson_password
output "backrest_mindy_password" {
  value     = module.backrest_mindy.ui_password
  sensitive = true
}
