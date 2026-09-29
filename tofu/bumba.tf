# 9443 is portainer, which tofu does not manage.
locals {
  bumba_ports = {
    traefik_http      = 80
    traefik_https     = 443
    storage_box_proxy = 2223
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

module "network_bumba" {
  source = "./modules/network"

  providers = { docker = docker.bumba }

  name = "traefik-network"
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
  ]

  network_name = module.network_bumba.name

  http_port  = local.bumba_ports.traefik_http
  https_port = local.bumba_ports.traefik_https
}

module "zitadel_server" {
  source = "./modules/services/zitadel"

  providers = {
    docker     = docker.bumba
    postgresql = postgresql.bumba
  }

  traefik_network = module.network_bumba.name
  db_network      = module.postgres_bumba.network_name

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

  traefik_network = module.network_bumba.name
  tailscale_ip    = var.bumba_addr

  zitadel_org_id = module.zitadel.org_home_id

  host_port = local.bumba_ports.gatus
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


