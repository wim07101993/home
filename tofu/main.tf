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

# Every database in the estate, on both hosts. One module, one file, grouped by
# host -- so "what databases exist?" has a single answer.
#
# Not the same layer as `modules/services/postgres`, which is the postgres
# CONTAINER (docker provider, one instance per host). This is the logical
# objects inside them.
#
# depends_on because the postgresql provider dials port 5432 directly over the
# tailnet, so nothing in the graph would otherwise order this after the
# containers. An apply that replaced one would race the connection -- the same
# failure as the zitadel provider one below, different port.
module "databases" {
  source = "./modules/databases"

  # Both hosts. The default is bumba's; mindy's is passed explicitly, which the
  # module accepts via configuration_aliases.
  providers = {
    postgresql       = postgresql
    postgresql.mindy = postgresql.mindy
  }

  depends_on = [module.postgres_bumba, module.postgres_mindy]
}

# State moves. Every one is a RENAME -- nothing live changes.
#
# Without them tofu sees the old addresses gone and the new ones absent, and
# plans to DROP three databases and recreate them empty. prevent_destroy would
# catch it -- by failing the apply, after the plan had already offered to
# destroy the data.
#
# 2026-09-18: modules/postgres -> modules/databases.
moved {
  from = module.postgres.postgresql_database.zitadel
  to   = module.databases.postgresql_database.zitadel
}

# 2026-09-18: score's and kitchen-owl's roles and databases centralised out of
# their service modules. The random_passwords move with them -- same generated
# values, so nothing rotates and neither container restarts.
moved {
  from = module.score.random_password.db
  to   = module.databases.random_password.score_api
}

moved {
  from = module.score.postgresql_role.api
  to   = module.databases.postgresql_role.score_api
}

moved {
  from = module.score.postgresql_database.this
  to   = module.databases.postgresql_database.score
}

moved {
  from = module.kitchen_owl.random_password.db
  to   = module.databases.random_password.kitchenowl
}

moved {
  from = module.kitchen_owl.postgresql_role.this
  to   = module.databases.postgresql_role.kitchenowl
}

moved {
  from = module.kitchen_owl.postgresql_database.this
  to   = module.databases.postgresql_database.kitchenowl
}

# memos is NOT moved -- it was never in tofu. It is imported; see imports.tf.

# SMTP credentials for outbound alerts. Credentials only -- the sending domain
# is deliberately unmanaged, see the module.
module "mailgun" {
  source = "./modules/mailgun"
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
  network_name   = "reverse-proxy_reverse-proxy-network"
  image_tag      = "v3.7.10"

  network_labels = {
    "com.docker.compose.config-hash" = "269096a0575268b819c342ef4a1d6d6c8240ce7cd8ddfb507530a7587d85e957"
    "com.docker.compose.network"     = "reverse-proxy-network"
    "com.docker.compose.project"     = "reverse-proxy"
    "com.docker.compose.version"     = ""
  }
}

# mindy's traefik. Same shape, different host. Cutover, not adoption.
module "reverse_proxy_mindy" {
  source = "./modules/services/reverse-proxy"

  providers = {
    docker = docker.mindy
  }

  host           = "mindy"
  container_name = "traefik"
  network_name   = "traefik_traefik-network"
  image_tag      = "v3.7.13"

  # From `docker network inspect traefik_traefik-network` on mindy,
  # 2026-09-17. Note the project is `traefik` and the hash is mindy's own --
  # these were briefly hardcoded to bumba's values, which would have stamped
  # this network with the wrong stack's identity.
  network_labels = {
    "com.docker.compose.config-hash" = "a28de9114d611e880f6424720a2fbf6580fde482deabb368bd099ee6e96b8c6c"
    "com.docker.compose.network"     = "traefik-network"
    "com.docker.compose.project"     = "traefik"
    "com.docker.compose.version"     = ""
  }
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

  # Zitadel's own outbound mail credential. Created by tofu, so there is no
  # SMTP password to type and rotating it is an apply.
  smtp_user     = module.mailgun.auth_smtp_username
  smtp_password = module.mailgun.auth_smtp_password

  depends_on = [module.reverse_proxy_bumba]
}

output "zitadel_apps" {
  description = "New client ids and secrets for the cutover. `tofu output -json zitadel_apps`."
  sensitive   = true
  value       = module.zitadel.apps
}

output "zitadel_project_ids" {
  value = module.zitadel.project_ids
}

# bumba's postgres. The container holding zitadel's database, score's, and --
# normally -- this state. See the module README before touching it.
module "postgres_bumba" {
  source = "./modules/services/postgres"

  providers = {
    docker = docker.bumba
  }

  container_name = "database-db-1"
  network_name   = "database_db-network"

  # From `docker network inspect database_db-network` on bumba, 2026-09-17.
  network_labels = {
    "com.docker.compose.config-hash" = "6723d56766a425ef676f8dc75eeff5a7178b8f4fb7298a50613bcf948efd9d78"
    "com.docker.compose.network"     = "db-network"
    "com.docker.compose.project"     = "database"
    "com.docker.compose.version"     = ""
  }
}

# it-tools.wvl.app. No database, no OIDC, no secrets -- the cheapest container
# to move, and therefore the one to prove the pattern on.
module "it_tools" {
  source = "./modules/services/it-tools"

  providers = {
    docker = docker.mindy
  }

  network_name = module.reverse_proxy_mindy.network_name
}

# mindy's postgres. memos and filebrowser depend on it. Unlike bumba's, it
# holds no tofu state, so no round-trip is needed.
module "postgres_mindy" {
  source = "./modules/services/postgres"

  providers = {
    docker = docker.mindy
  }

  container_name = "db"
  network_name   = "db_db-network"

  # From `docker network inspect db_db-network` on mindy, 2026-09-17. The
  # project is `db` here and `database` on bumba -- reproducing bumba's would
  # stamp this network with the wrong stack's identity.
  network_labels = {
    "com.docker.compose.config-hash" = "c84a1ab54cb8990da8545ea8c010f473d33fe3a55851f06124cd5831ae855a9b"
    "com.docker.compose.network"     = "db-network"
    "com.docker.compose.project"     = "db"
    "com.docker.compose.version"     = ""
  }
}

# memo.wvl.app. First container with a database dependency and a secret.
module "memo" {
  source = "./modules/services/memo"

  providers = {
    docker = docker.mindy
  }

  traefik_network = module.reverse_proxy_mindy.network_name
  db_network      = module.postgres_mindy.network_name

  db_user     = module.databases.memos.user
  db_password = module.databases.memos.password
  db_name     = module.databases.memos.name

  # The db_network reference orders this after the NETWORK, not after the
  # database container -- so tofu created both in parallel on 2026-09-17 and
  # memos' first connection attempt raced postgres' startup. `unless-stopped`
  # covered it, but relying on a restart policy for ordering is luck.
  depends_on = [module.postgres_mindy]
}

# drive.wvl.app. The one with rslave-propagated NFS mounts under it.
module "file_browser" {
  source = "./modules/services/file-browser"

  providers = {
    docker = docker.mindy
  }

  traefik_network = module.reverse_proxy_mindy.network_name
  db_network      = module.postgres_mindy.network_name

  depends_on = [module.postgres_mindy]
}

# homepage.wvl.app -- the dashboard.
module "homepage" {
  source = "./modules/services/homepage"

  providers = {
    docker = docker.mindy
  }

  traefik_network = module.reverse_proxy_mindy.network_name
}

# score.wvl.app / partituren.wvl.app / score-api.wvl.app
#
# Moved from bumba to mindy AND cut over to the rebuilt zitadel apps in one
# change, because the config files had to be rewritten either way -- the
# connection string changes with the host. Doing it in two passes would have
# meant hand-editing them once and regenerating them later.
module "score" {
  source = "./modules/services/score"

  providers = {
    docker = docker.mindy
  }

  traefik_network = module.reverse_proxy_mindy.network_name
  db_network      = module.postgres_mindy.network_name

  db_user     = module.databases.score.user
  db_password = module.databases.score.password
  db_name     = module.databases.score.name

  api_client_id     = module.zitadel.apps["Score/score-api"].client_id
  api_client_secret = module.zitadel.apps["Score/score-api"].client_secret
  web_client_id     = module.zitadel.apps["Score/score-web-app"].client_id

  depends_on = [module.postgres_mindy]
}

# photos.wvl.app -- four containers, an NFS library from samson, and immich's
# own pgvector postgres.
module "immich" {
  source = "./modules/services/immich"

  providers = {
    docker = docker.mindy
  }

  traefik_network = module.reverse_proxy_mindy.network_name
  db_password     = var.immich_db_password
}

# keuken.wvl.app. Moved onto the shared postgres, off its own postgres:15.
module "kitchen_owl" {
  source = "./modules/services/kitchen-owl"

  providers = {
    docker = docker.mindy
  }

  traefik_network = module.reverse_proxy_mindy.network_name
  db_network      = module.postgres_mindy.network_name

  db_user     = module.databases.kitchenowl.user
  db_password = module.databases.kitchenowl.password
  db_name     = module.databases.kitchenowl.name

  oidc_client_id     = module.zitadel.apps["keuken/kitchen owl web-app"].client_id
  oidc_client_secret = module.zitadel.apps["keuken/kitchen owl web-app"].client_secret

  depends_on = [module.postgres_mindy]
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
    docker = docker.bumba
  }

  traefik_network = module.reverse_proxy_bumba.network_name
  tailscale_ip    = var.bumba_addr

  oidc_client_id     = module.zitadel.apps["status/gatus"].client_id
  oidc_client_secret = module.zitadel.apps["status/gatus"].client_secret

  # Created by tofu rather than typed in: modules/mailgun mints this credential
  # and the value never leaves the graph.
  smtp_username = module.mailgun.gatus_smtp_username
  smtp_password = module.mailgun.gatus_smtp_password
}

# For wiring kopia's post-snapshot push. The token is the only credential that
# can report a backup as successful, so it is sensitive:
#
#   tofu output -raw gatus_kopia_push_token
output "gatus_kopia_push_token" {
  description = "Bearer token for kopia's heartbeat push to gatus."
  sensitive   = true
  value       = module.gatus.kopia_push_token
}

output "gatus_kopia_push_url" {
  value = module.gatus.kopia_push_url
}
