# bumba -- cpx11 in fsn1. The public front door, the state backend, identity and
# the monitoring that must not live on the machines it watches.
#
# Every module here takes docker.bumba. See providers.tf for why the alias is
# explicit and there is no default.

# The traefik networks, one per host. Extracted from the reverse-proxy module so
# that routing can be sliced per service without a dependency cycle -- see
# modules/network.
module "network_bumba" {
  source = "./modules/network"

  providers = { docker = docker.bumba }

  name = "reverse-proxy_reverse-proxy-network"
  labels = {
    "com.docker.compose.config-hash" = "269096a0575268b819c342ef4a1d6d6c8240ce7cd8ddfb507530a7587d85e957"
    "com.docker.compose.network"     = "reverse-proxy-network"
    "com.docker.compose.project"     = "reverse-proxy"
    "com.docker.compose.version"     = ""
  }
}

# bumba's traefik. A cutover, not an adoption -- see the module README.
# mindy's traefik stays on compose for now.
module "reverse_proxy_bumba" {
  source = "./modules/services/reverse-proxy"

  providers = {
    docker = docker.bumba
  }

  host           = "bumba"
  container_name = "reverse-proxy"
  network_name   = module.network_bumba.name
  dashboard_host = "wvl.app"

  routing = [
    module.zitadel_server.traefik,
    module.gatus.traefik,
  ]

}

# auth.wvl.app's CONTAINERS. A cutover from the portainer git stack -- see the
# module. `zitadel_server` is the deployment; `zitadel` below is its contents.
#
# depends_on the NETWORK, not the proxy. It used to be module.reverse_proxy_bumba
# because that module created the network; now routing flows the other way --
# the proxy consumes this module's `traefik` output -- and naming the proxy here
# is a cycle:
#
#   Cycle: module.zitadel_server (expand), module.zitadel_server.output.traefik,
#          module.reverse_proxy_bumba.var.routing, ...
#
# depends_on because both containers attach to networks these modules own, and
# because zitadel cannot start before its database container exists.
module "zitadel_server" {
  source = "./modules/services/zitadel"

  # A VERTICAL SLICE: zitadel owns its own database and roles, on bumba.
  providers = {
    docker     = docker.bumba
    postgresql = postgresql
  }

  traefik_network = module.network_bumba.name
  db_network      = module.postgres_bumba.network_name

  depends_on = [module.postgres_bumba, module.network_bumba]
}

# Projects, roles and OIDC applications. A REBUILD, not an adoption -- orgs
# and users are deliberately untouched. modules/zitadel/orgs.tf says why.
#
# depends_on because the zitadel PROVIDER talks to auth.wvl.app, which is served
# by bumba's traefik. Nothing else in the graph expresses that, so tofu is free
# to replace traefik and call the zitadel API at the same moment.
#
# It did, on 2026-09-17:
#
#   module.reverse_proxy_bumba.docker_container.this: Destroying...
#   module.zitadel.zitadel_project.status: Creating...
#   Error: dial tcp 5.75.247.152:443: connect: connection refused
#
# Traefik was down for ONE SECOND and the apply failed half-finished. Changing
# dynamic.yml replaces the container, so this is a hazard on any routing change,
# not a one-off.
module "zitadel" {
  source = "./modules/zitadel"

  # The SMTP credential is no longer passed in -- the module owns it, in
  # modules/zitadel/mail.tf, beside the config that authenticates with it.

  depends_on = [module.reverse_proxy_bumba, module.zitadel_server]
}

# bumba's postgres. The container holding zitadel's database, score's, and --
# normally -- this state. See the module README before touching it.
module "postgres_bumba" {
  source = "./modules/services/postgres"

  providers = {
    docker = docker.bumba
  }
}

# The hop that lets samson and plop reach the Storage Box at all.
#
# On bumba because bumba is in Hetzner and is already a single point of failure
# -- it holds this layer's state and the monitoring -- so routing through it
# adds no new one. mindy would have worked equally well technically, and was
# rejected so the machine taking snapshots is not also the one every other host
# depends on to store them.
module "storage_box_proxy" {
  source = "./modules/services/storage-box-proxy"

  providers = {
    docker = docker.bumba
  }

  target_host  = module.hetzner.storage_box_host
  tailscale_ip = var.bumba_addr
}

# status.wvl.app -- service monitoring, on bumba. The first service here that
# is created rather than migrated.
#
# Was uptime-kuma. Swapped for gatus because uptime-kuma's monitors live in a
# SQLite database behind a UI: they cannot be expressed here, reviewed in a
# diff, or restored from this repo. It ran for a week with zero monitors
# configured and nothing said so -- which is the same class of silent failure
# this service exists to catch.
module "gatus" {
  source = "./modules/services/gatus"

  providers = {
    docker  = docker.bumba
    zitadel = zitadel
  }

  traefik_network = module.network_bumba.name
  tailscale_ip    = var.bumba_addr

  zitadel_org_id = module.zitadel.org_home_id

  # The SMTP credential is not passed in: the module mints its own, in
  # modules/services/gatus/mail.tf, and the value never leaves the graph.
}

# --- inputs ---------------------------------------------------------------

# One address, used by both the postgresql provider and the docker provider.
variable "bumba_addr" {
  type        = string
  description = "bumba's TAILNET address. Never the public IP: postgres runs sslmode=disable and relies on WireGuard for transport security."
}

variable "pg_superuser_password" {
  type        = string
  sensitive   = true
  description = "postgres superuser password, from /docker-volumes/db/db_password.txt on bumba."
}

# --- outputs --------------------------------------------------------------

# Assembled from the instance-level module and each vertical slice. The cutover
# needs every client id in one place even though the resources now live with the
# service that uses them.
output "zitadel_apps" {
  description = "New client ids and secrets for the cutover. `tofu output -json zitadel_apps`."
  sensitive   = true
  value = merge(
    module.score.zitadel_apps,
    {
      "home/home assistant"        = module.home_assistant.zitadel_app
      "memo/memo"                  = module.memo.zitadel_app
      "keuken/kitchen owl web-app" = module.kitchen_owl.zitadel_app
      "status/gatus"               = module.gatus.zitadel_app
      "photos/immich"              = module.immich.zitadel_app
      "drive/drive"                = module.file_browser.zitadel_app
    },
  )
}

output "zitadel_project_ids" {
  value = {
    "home"   = module.home_assistant.zitadel_project_id
    "memo"   = module.memo.zitadel_project_id
    "keuken" = module.kitchen_owl.zitadel_project_id
    "status" = module.gatus.zitadel_project_id
    "photos" = module.immich.zitadel_project_id
    "drive"  = module.file_browser.zitadel_project_id
    "Score"  = module.score.zitadel_project_id
  }
}

output "gatus_kopia_push_token" {
  description = "Bearer token for kopia's heartbeat push to gatus."
  sensitive   = true
  value       = module.gatus.kopia_push_token
}

output "gatus_kopia_push_url" {
  value = module.gatus.kopia_push_url
}
