locals {
  bumba_ports = {
    traefik_http      = 80
    traefik_https     = 443
    storage_box_proxy = 2223
    smtp_relay        = 2525
    zitadel           = 3001
    zitadel_login     = 3002
    gatus             = 3009
    postgres          = 5432
  }
}

check "bumba_unique_ports" {
  assert {
    condition     = length(values(local.bumba_ports)) == length(distinct(values(local.bumba_ports)))
    error_message = "two services in bumba.tf are published on the same host port"
  }
}

module "smtp_relay_bumba" {
  source = "./modules/services/smtp-relay"

  providers = {
    docker = docker.bumba
  }

  login     = "bumba"
  host_port = local.bumba_ports.smtp_relay
}

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
    module.ntfy.traefik,
  ]

  http_port  = local.bumba_ports.traefik_http
  https_port = local.bumba_ports.traefik_https
}

module "zitadel_server" {
  source = "./modules/services/zitadel"

  providers = {
    docker     = docker.bumba
    postgresql = postgresql.bumba
  }

  db_network = module.postgres_bumba.network_names["zitadel"]

  depends_on = [module.postgres_bumba]

  # published on the host
  host_port       = local.bumba_ports.zitadel
  login_host_port = local.bumba_ports.zitadel_login
}

module "zitadel" {
  source = "./modules/zitadel"

  depends_on = [module.zitadel_server]
}

module "postgres_bumba" {
  source = "./modules/services/postgres"

  providers = {
    docker = docker.bumba
  }

  host_port = local.bumba_ports.postgres

  clients = ["zitadel"]
}

module "storage_box_proxy" {
  source = "./modules/services/storage-box-proxy"

  providers = {
    docker = docker.bumba
  }

  target_host  = module.hetzner.storage_box_host
  tailscale_ip = var.bumba_addr

  listen_port = local.bumba_ports.storage_box_proxy
}

module "gatus" {
  source = "./modules/services/gatus"

  providers = {
    docker  = docker.bumba
    zitadel = zitadel
  }

  tailscale_ip = var.bumba_addr

  zitadel_org_id = module.zitadel.org_home_id

  ntfy       = module.ntfy.gatus
  ntfy_token = module.ntfy.gatus_token

  host_port = local.bumba_ports.gatus
}

module "ntfy" {
  source = "./modules/services/ntfy"

  providers = {
    docker = docker.bumba
  }
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
      "portal/home portal (dev)"   = module.portal.zitadel_app_dev
      "docker/arcane"              = module.arcane.zitadel_app
      "tasks/donetick"             = module.donetick.zitadel_app
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
    "portal" = module.portal.zitadel_project_id
    "docker" = module.arcane.zitadel_project_id
    "tasks"  = module.donetick.zitadel_project_id
  }
}

output "ntfy_password" {
  description = "The phone app's login on https://ntfy.wvl.app, user wim. `tofu output -raw ntfy_password`."
  value       = module.ntfy.wim_password
  sensitive   = true
}

output "donetick_webhook_url" {
  description = "Donetick's circle webhook (Settings -> Webhook): ntfy's tasks topic, with its token. `tofu output -raw donetick_webhook_url`."
  value       = module.ntfy.donetick_webhook_url
  sensitive   = true
}

output "traefik_bumba_password" {
  value     = module.reverse_proxy_bumba.dashboard_password
  sensitive = true
}


