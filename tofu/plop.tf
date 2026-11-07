# matterjs-server publishes nothing.
locals {
  plop_ports = {
    home_assistant   = 8123
    adguard_home     = 3000
    adguard_home_dns = 53
    smtp_relay       = 2525
    backrest         = 9898
  }
}

check "plop_unique_ports" {
  assert {
    condition     = length(values(local.plop_ports)) == length(distinct(values(local.plop_ports)))
    error_message = "two services in plop.tf are published on the same host port"
  }
}

module "smtp_relay_plop" {
  source = "./modules/services/smtp-relay"

  providers = {
    docker = docker.plop
  }

  login     = "plop"
  host_port = local.plop_ports.smtp_relay
}

module "home_assistant" {
  source = "./modules/services/home-assistant"

  providers = {
    docker  = docker.plop
    zitadel = zitadel
  }

  zitadel_org_id = module.zitadel.org_home_id
  tailscale_ip   = var.plop_addr

  host_port = local.plop_ports.home_assistant
}

# Shared by both AdGuard Home instances, this one and samson's, which the
# router hands out side by side. Clients use either, so they must answer alike.
locals {
  adguard = {
    router_addr = "10.0.0.1"
    dns_records = {
      "mindy.home" = var.mindy_addr
      "bumba.home" = var.bumba_addr
    }
  }
}

module "adguard_home" {
  source = "./modules/services/adguard-home"

  providers = {
    docker  = docker.plop
    adguard = adguard
  }

  router_addr = local.adguard.router_addr
  dns_records = local.adguard.dns_records

  host_port = local.plop_ports.adguard_home
  dns_port  = local.plop_ports.adguard_home_dns
}

module "backrest_plop" {
  source = "./modules/services/backrest"

  providers = {
    docker = docker.plop
  }

  instance     = "plop"
  tailscale_ip = var.plop_addr

  backup = [
    module.home_assistant.backup,
    module.adguard_home.backup,
  ]

  repository_password = random_password.backrest_repository.result

  # backup everything to both snow-white and samson
  storage_box = {
    id   = module.hetzner.storage_box_id
    host = module.hetzner.storage_box_host

    # Through bumba, like samson: from home the Storage Box offers no way in.
    via = { host = var.bumba_addr, port = module.storage_box_proxy.listen_port }
  }
  rest_server = {
    name = "samson"
    url  = "http://${var.samson_addr}:${local.samson_ports.rest_server}"
  }

  port = local.plop_ports.backrest
}

# --- inputs ---------------------------------------------------------------

variable "plop_addr" {
  type        = string
  description = "plop's TAILNET address. Home Assistant, the Matter server and AdGuard Home's API; reached as wim over SSH for the docker provider."
}

# --- outputs --------------------------------------------------------------

output "adguard_home_password" {
  value     = module.adguard_home.admin_password
  sensitive = true
}

output "backrest_plop_password" {
  value     = module.backrest_plop.ui_password
  sensitive = true
}
