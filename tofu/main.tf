# One root module, several child modules. One state, one init, one apply --
# the directories are for reading, not for isolation.
#
# Providers are configured once, in providers.tf, and inherited. No child
# declares a provider block, so there is exactly one place the Hetzner token,
# the postgres superuser password and the docker endpoints are wired in.
#
# Service modules take their docker provider explicitly rather than inheriting
# a default. There is no default on purpose:
# `docker.bumba` and `docker.mindy` point at different daemons, and an apply
# against the wrong one recreates the wrong front door.

module "hetzner" {
  source = "./modules/hetzner"

  storage_box_password = var.storage_box_password
}

module "postgres" {
  source = "./modules/postgres"
}

# bumba's traefik. A cutover, not an adoption -- see the module README.
# mindy's traefik stays on compose for now.
module "reverse_proxy_bumba" {
  source = "./modules/services/reverse-proxy"

  providers = {
    docker = docker.bumba
  }
}
