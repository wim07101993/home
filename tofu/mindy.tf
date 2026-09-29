# 9443 is portainer, which tofu does not manage.
locals {
  mindy_ports = {
    traefik_http    = 80
    traefik_https   = 443
    immich          = 2283
    homepage        = 3001
    score_web       = 3006
    memos           = 5230
    postgres        = 5432
    immich_postgres = 5434
    score_api       = 7001
    filebrowser     = 8900
    backrest        = 9898
  }
}

check "mindy_unique_ports" {
  assert {
    condition     = length(values(local.mindy_ports)) == length(distinct(values(local.mindy_ports)))
    error_message = "two services in mindy.tf are published on the same host port"
  }
}

module "network_mindy" {
  source = "./modules/network"

  providers = { docker = docker.mindy }

  name = "traefik-network"
}

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
  network_name = module.network_mindy.name

  http_port  = local.mindy_ports.traefik_http
  https_port = local.mindy_ports.traefik_https
}

module "it_tools" {
  source = "./modules/services/it-tools"

  providers = {
    docker = docker.mindy
  }

  traefik_network = module.network_mindy.name
}

module "postgres_mindy" {
  source = "./modules/services/postgres"

  providers = {
    docker = docker.mindy
  }

  host_port = local.mindy_ports.postgres
}

module "memo" {
  source = "./modules/services/memo"

  providers = {
    docker     = docker.mindy
    postgresql = postgresql.mindy
    zitadel    = zitadel
  }

  traefik_network = module.network_mindy.name
  db_network      = module.postgres_mindy.network_name

  zitadel_org_id = module.zitadel.org_home_id

  depends_on = [module.postgres_mindy]

  host_port = local.mindy_ports.memos
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

  traefik_network = module.network_mindy.name

  zitadel_org_id = module.zitadel.org_home_id

  host_port = local.mindy_ports.filebrowser
}

module "homepage" {
  source = "./modules/services/homepage"

  providers = {
    docker = docker.mindy
  }

  traefik_network = module.network_mindy.name

  host_port = local.mindy_ports.homepage
}

module "score" {
  source = "./modules/services/score"

  providers = {
    docker     = docker.mindy
    postgresql = postgresql.mindy
    zitadel    = zitadel
  }

  traefik_network = module.network_mindy.name
  db_network      = module.postgres_mindy.network_name

  zitadel_org_id = module.zitadel.org_home_id

  depends_on = [module.postgres_mindy]

  api_host_port = local.mindy_ports.score_api
  web_host_port = local.mindy_ports.score_web
}

module "kitchen_owl" {
  source = "./modules/services/kitchen-owl"

  providers = {
    docker     = docker.mindy
    postgresql = postgresql.mindy
    zitadel    = zitadel
  }

  traefik_network = module.network_mindy.name
  db_network      = module.postgres_mindy.network_name

  zitadel_org_id = module.zitadel.org_home_id

  depends_on = [module.postgres_mindy]
}

module "immich" {
  source = "./modules/services/immich"

  providers = {
    docker     = docker.mindy
    zitadel    = zitadel
    postgresql = postgresql.immich
  }

  library_path    = local.photos_path
  traefik_network = module.network_mindy.name

  zitadel_org_id = module.zitadel.org_home_id

  superuser_password = var.immich_pg_superuser_password

  host_port    = local.mindy_ports.immich
  db_host_port = local.mindy_ports.immich_postgres
}


module "backrest_mindy" {
  source = "./modules/services/backrest"

  providers = {
    docker = docker.mindy
  }

  instance     = "mindy"
  tailscale_ip = var.mindy_addr

  # What kopia used to back up, at /backup instead of its old /data -- see the
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

  port = local.mindy_ports.backrest
}

# --- values ---------------------------------------------------------------

locals {
  photos_path    = "/mnt/rafiki/photos"
  documents_path = "/mnt/rafiki/documents"
  audio_path     = "/mnt/rafiki/audio"
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

variable "mindy_pg_superuser_password" {
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


output "backrest_mindy_password" {
  value     = module.backrest_mindy.ui_password
  sensitive = true
}
