# One root module, two child modules. One state, one init, one apply --
# the directories are for reading, not for isolation.
#
# Providers are configured once, in providers.tf, and inherited. Neither child
# declares a provider block, so there is exactly one place the Hetzner token
# and the postgres superuser password are wired in.

module "hetzner" {
  source = "./modules/hetzner"

  storage_box_password = var.storage_box_password
}

module "postgres" {
  source = "./modules/postgres"
}
