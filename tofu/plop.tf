# 9443 is portainer, which tofu does not manage. matterjs-server publishes
# nothing.
locals {
  plop_ports = {
    home_assistant = 8123
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

# --- inputs ---------------------------------------------------------------

variable "plop_addr" {
  type        = string
  description = "plop's TAILNET address. Home Assistant and the Matter server; reached as root over SSH for the docker provider."
}
