# plop -- on the home LAN, domestic power and uplink. The most likely of the
# four to be unreachable when you want to plan something unrelated; see
# providers.tf.
#
# Every module here takes docker.plop.

# Home Assistant and the Matter server on plop.
#
# CUT OVER FROM A PORTAINER STACK, and this one is NOT a plain stack delete:
# the Matter fabric is in an anonymous docker volume that the delete can
# destroy. Read the module README first.
#
# The zitadel client for Home Assistant is in ../zitadel rather than here --
# it predates this module, and moving it is a separate `moved` block.
module "home_assistant" {
  source = "./modules/services/home-assistant"

  providers = {
    docker  = docker.plop
    zitadel = zitadel
  }

  org_id       = module.zitadel.org_home_id
  tailscale_ip = var.plop_addr
}

# --- inputs ---------------------------------------------------------------

variable "plop_addr" {
  type        = string
  description = "plop's TAILNET address. Home Assistant and the Matter server; reached as root over SSH for the docker provider."
}
