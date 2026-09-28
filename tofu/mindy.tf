module "traefik_mindy" {
  source = "./modules/services/reverse-proxy"

  providers = {
    docker = docker.mindy
  }

  host           = "mindy"
  container_name = "traefik"
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
}

module "it_tools" {
  source = "./modules/services/it-tools"

  providers = {
    docker = docker.mindy
  }

  traefik_network = module.traefik_mindy.network_name
}

module "postgres_mindy" {
  source    = "./modules/services/postgres"

  providers = {
    docker = docker.mindy
  }
}

module "memo" {
  source = "./modules/services/memo"

  providers = {
    docker     = docker.mindy
    postgresql = postgresql.mindy
    zitadel    = zitadel
  }

  traefik_network = module.traefik_mindy.network_name
  db_network      = module.postgres_mindy.network_name

  org_id = module.zitadel.org_home_id

  depends_on = [module.postgres_mindy]
}

module "file_browser" {
  source = "./modules/services/file-browser"

  providers = {
    docker  = docker.mindy
    zitadel = zitadel
  }

  audio_path      = local.audio_path
  documents_path  = local.documents_path
  document_shares = local.document_shares

  sources = [
    { path = "/files/gezin-officieel", name = "Gezin officieel", default_enabled = true },
    { path = "/files/gezin-officieel-archive", name = "Gezin officieel archive", default_enabled = true },
    { path = "/files/audio", name = "Audio", default_enabled = true },
    { path = "/files/audio-archive", name = "Audio archive", default_enabled = true },
    { path = "/files/wim", name = "Wim privé", default_enabled = false },
    { path = "/files/sara", name = "Sara prive", default_enabled = false },
  ]

  # TODO this client_id should not be hardcoded
  oidc_client_id = "367153386023354372"

  traefik_network = module.traefik_mindy.network_name

  org_id = module.zitadel.org_home_id
}

module "homepage" {
  source = "./modules/services/homepage"

  providers = {
    docker = docker.mindy
  }

  traefik_network = module.traefik_mindy.network_name
}

module "score" {
  source = "./modules/services/score"

  providers = {
    docker     = docker.mindy
    postgresql = postgresql.mindy
    zitadel    = zitadel
  }

  traefik_network = module.traefik_mindy.network_name
  db_network      = module.postgres_mindy.network_name

  # TODO rename org_id everywhere to zitadel_org_id
  org_id = module.zitadel.org_home_id

  depends_on = [module.postgres_mindy]
}

module "kitchen_owl" {
  source = "./modules/services/kitchen-owl"

  providers = {
    docker     = docker.mindy
    postgresql = postgresql.mindy
    zitadel    = zitadel
  }

  traefik_network = module.traefik_mindy.network_name
  db_network      = module.postgres_mindy.network_name

  org_id = module.zitadel.org_home_id

  depends_on = [module.postgres_mindy]
}

module "immich" {
  source = "./modules/services/immich"

  providers = {
    docker  = docker.mindy
    zitadel = zitadel
    # TODO: shouldn't this be in the immich module anyway? Why do we need to specify the pg
    postgresql = postgresql.immich
  }

  library_path    = local.photos_path
  traefik_network = module.traefik_mindy.network_name

  org_id = module.zitadel.org_home_id

  superuser_password = var.immich_pg_superuser_password
}

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
  sftp_username       = module.hetzner.storage_box_sftp_username
  sftp_host           = module.hetzner.storage_box_host
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
  storage_box_id      = module.hetzner.storage_box_id
  sftp_host           = module.hetzner.storage_box_host

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

locals {
  photos_path = "/mnt/rafiki/photos"
  documents_path = "/mnt/rafiki/documents"
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

output "filebrowser_admin_password" {
  value     = module.file_browser.admin_password
  sensitive = true
}

output "kopia_mindy_password" {
  value     = module.kopia.server_password
  sensitive = true
}

output "backrest_mindy_password" {
  value     = module.backrest_mindy.ui_password
  sensitive = true
}
