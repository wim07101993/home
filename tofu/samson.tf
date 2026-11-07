# plex and ftp use network_mode = "host", so they publish nothing through docker
# -- plex's 32400 and friends and ftp's 21 and 21000-21010 are taken but cannot
# appear here.
locals {
  samson_ports = {
    databasus   = 4005
    navidrome   = 4533
    backrest    = 9898
    smtp_relay  = 2525
    rest_server = 8000
  }
}

check "samson_unique_ports" {
  assert {
    condition     = length(values(local.samson_ports)) == length(distinct(values(local.samson_ports)))
    error_message = "two services in samson.tf are published on the same host port"
  }
}

module "databasus" {
  source = "./modules/services/databasus"

  providers = {
    docker = docker.samson
  }

  host_port = local.samson_ports.databasus
}

module "smtp_relay" {
  source = "./modules/services/smtp-relay"

  providers = {
    docker = docker.samson
  }

  login     = "samson"
  host_port = local.samson_ports.smtp_relay
}

module "ftp" {
  source = "./modules/services/ftp"

  providers = {
    docker = docker.samson
  }

  media_path         = "/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300/media"
  audio_archive_path = "/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300/audio-archive"
}

module "plex" {
  source = "./modules/services/plex"

  providers = {
    docker = docker.samson
  }
}

# Public at music.wvl.app through mindy
module "navidrome" {
  source = "./modules/services/navidrome"

  providers = {
    docker = docker.samson
  }

  tailscale_ip = var.samson_addr

  host_port = local.samson_ports.navidrome
}


module "rest_server" {
  source = "./modules/services/rest-server"

  providers = {
    docker = docker.samson
  }

  tailscale_ip = var.samson_addr
  port         = local.samson_ports.rest_server
  data_path    = "/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300/backups/rest-server"

  clients = [
    module.backrest_mindy.rest_server_account,
    module.backrest_plop.rest_server_account,
    # bumba does not hold any files
  ]
}

module "backrest_samson" {
  source = "./modules/services/backrest"

  providers = {
    docker = docker.samson
  }

  instance     = "samson"
  tailscale_ip = var.samson_addr
  config_path  = "/docker-volumes/backrest"

  backup = [
    module.plex.backup,
    module.databasus.backup,
    module.navidrome.backup,

    { paths = ["/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300/audio-archive"] },
  ]

  repository_password = random_password.backrest_repository.result

  # backup everything to snow-white
  storage_box = {
    id   = module.hetzner.storage_box_id
    host = module.hetzner.storage_box_host

    # Through bumba. samson cannot authenticate to the Storage Box directly.
    via = { host = var.bumba_addr, port = module.storage_box_proxy.listen_port }
  }

  port = local.samson_ports.backrest
}

# --- values ---------------------------------------------------------------

locals {
}

# --- inputs ---------------------------------------------------------------

variable "samson_addr" {
  type        = string
  description = "samson's TAILNET address. Reached as wim over SSH for the docker provider."
}

# --- outputs --------------------------------------------------------------


output "navidrome_admin_password" {
  value     = module.navidrome.admin_password
  sensitive = true
}

output "ftp_password" {
  value     = module.ftp.password
  sensitive = true
}

output "backrest_samson_password" {
  value     = module.backrest_samson.ui_password
  sensitive = true
}
