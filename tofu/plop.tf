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

module "backrest_plop" {
  source = "./modules/services/backrest"

  providers = {
    docker = docker.plop
  }

  instance     = "plop"
  tailscale_ip = var.plop_addr

  # The matter server's folder belongs to the host's matter account, and
  # AdGuard Home's to its remapped uid, mode 0700: remapped root reads neither.
  userns_mode = "host"

  backup = [
    module.home_assistant.backup,
    module.adguard_home.backup,
  ]

  repository_password = random_password.backrest_repository.result
  repo_path           = "restic"
  storage_box_id      = module.hetzner.storage_box_id
  sftp_host           = module.hetzner.storage_box_host

  # Through bumba, like samson: from home the Storage Box offers no way in.
  connect_host = var.bumba_addr
  connect_port = module.storage_box_proxy.listen_port

  gatus_token    = module.gatus.backrest_push_token
  gatus_base_url = module.gatus.external_endpoint_base_url
  gatus_endpoint = "backups_backrest-plop"

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
