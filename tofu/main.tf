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
