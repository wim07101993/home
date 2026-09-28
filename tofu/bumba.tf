module "reverse_proxy_bumba" {
  source = "./modules/services/reverse-proxy"

  providers = {
    docker = docker.bumba
  }

  host           = "bumba"
  container_name = "reverse-proxy"
  dashboard_host = "wvl.app"

  routing = [
    module.zitadel_server.traefik,
    module.gatus.traefik,
  ]

}

module "zitadel_server" {
  source = "./modules/services/zitadel"

  # A VERTICAL SLICE: zitadel owns its own database and roles, on bumba.
  providers = {
    docker     = docker.bumba
    postgresql = postgresql
  }

  traefik_network = module.reverse_proxy_bumba.network_name
  db_network      = module.postgres_bumba.network_name

  depends_on = [module.postgres_bumba, module.reverse_proxy_bumba]
}

module "zitadel" {
  source = "./modules/zitadel"

  depends_on = [module.reverse_proxy_bumba, module.zitadel_server]
}

module "postgres_bumba" {
  source = "./modules/services/postgres"

  providers = {
    docker = docker.bumba
  }
}

module "storage_box_proxy" {
  source = "./modules/services/storage-box-proxy"

  providers = {
    docker = docker.bumba
  }

  target_host  = module.hetzner.storage_box_host
  tailscale_ip = var.bumba_addr
}

module "gatus" {
  source = "./modules/services/gatus"

  providers = {
    docker  = docker.bumba
    zitadel = zitadel
  }

  traefik_network = module.reverse_proxy_bumba.network_name
  tailscale_ip    = var.bumba_addr

  zitadel_org_id = module.zitadel.org_home_id
}

# --- inputs ---------------------------------------------------------------

variable "bumba_addr" {
  type        = string
  description = "bumba's TAILNET address. Never the public IP: postgres runs sslmode=disable and relies on WireGuard for transport security."
}

variable "bumba_pg_superuser_password" {
  type        = string
  sensitive   = true
  description = "postgres superuser password, from /docker-volumes/db/db_password.txt on bumba."
}

# --- outputs --------------------------------------------------------------

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

output "gatus_kopia_push_token" {
  description = "Bearer token for kopia's heartbeat push to gatus."
  sensitive   = true
  value       = module.gatus.kopia_push_token
}

output "gatus_kopia_push_url" {
  value = module.gatus.kopia_push_url
}
