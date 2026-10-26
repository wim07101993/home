# matterjs-server publishes nothing.
locals {
  plop_ports = {
    home_assistant   = 8123
    adguard_home     = 3000
    adguard_home_dns = 53
  }
}

check "plop_unique_ports" {
  assert {
    condition     = length(values(local.plop_ports)) == length(distinct(values(local.plop_ports)))
    error_message = "two services in plop.tf are published on the same host port"
  }
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

module "adguard_home" {
  source = "./modules/services/adguard-home"

  providers = {
    docker  = docker.plop
    adguard = adguard
  }

  router_addr = "10.0.0.1"

  dns_records = {
    "mindy.home" = var.mindy_addr
    "bumba.home" = var.bumba_addr
  }

  host_port = local.plop_ports.adguard_home
  dns_port  = local.plop_ports.adguard_home_dns
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
