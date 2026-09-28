module "home_assistant" {
  source = "./modules/services/home-assistant"

  providers = {
    docker  = docker.plop
    zitadel = zitadel
  }

  zitadel_org_id = module.zitadel.org_home_id
  tailscale_ip   = var.plop_addr
}

# --- inputs ---------------------------------------------------------------

variable "plop_addr" {
  type        = string
  description = "plop's TAILNET address. Home Assistant and the Matter server; reached as root over SSH for the docker provider."
}
