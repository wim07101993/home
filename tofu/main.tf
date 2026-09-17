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


# Projects, roles and OIDC applications. A REBUILD, not an adoption -- orgs
# and users are deliberately untouched. modules/zitadel/orgs.tf says why.
module "zitadel" {
  source = "./modules/zitadel"
}

output "zitadel_apps" {
  description = "New client ids and secrets for the cutover. `tofu output -json zitadel_apps`."
  sensitive   = true
  value       = module.zitadel.apps
}

output "zitadel_project_ids" {
  value = module.zitadel.project_ids
}
