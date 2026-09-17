# score.wvl.app, partituren.wvl.app, score-api.wvl.app
#
# Moved from bumba to mindy on 2026-09-17, and cut over to the rebuilt zitadel
# applications in the same change.
#
# This is the module the whole workload layer was argued for. Everything below
# is one dependency graph, and compose could express none of it:
#
#   random_password ─> postgresql_role ─┐
#   zitadel client id + secret ─────────┴─> generated config ─> container
#
# No secret is typed by a human, and no client id is pasted into a file.

resource "random_password" "db" {
  length = 32

  # No special characters: this value goes into a libpq keyword/value DSN,
  # where an unescaped quote or backslash silently changes what connects
  # where. The same class of bug as the `p@ss` that broke PG_CONN_STR on
  # 2026-09-16.
  special = false
}

resource "postgresql_role" "api" {
  name     = "score_api"
  login    = true
  password = random_password.db.result
}

resource "postgresql_database" "this" {
  name  = "score"
  owner = postgresql_role.api.name

  lifecycle {
    prevent_destroy = true
  }
}

# --- the API ------------------------------------------------------------

locals {
  # host=db is the network ALIAS on mindy's postgres, the same name it had on
  # bumba -- which is why the host move needs no change here.
  api_secrets = jsonencode({
    dbConnectionString = join(" ", [
      "user=${postgresql_role.api.name}",
      "password=${random_password.db.result}",
      "host=db",
      "port=5432",
      "dbname=${postgresql_database.this.name}",
      "sslmode=disable",
    ])

    tokenIntrospectionUrl          = "https://auth.wvl.app/oauth/v2/introspect"
    userInfoUrl                    = "https://auth.wvl.app/oidc/v1/userinfo"
    rolesKey                       = "urn:zitadel:iam:org:project:roles"
    tokenIntrospectionClientId     = var.api_client_id
    tokenIntrospectionClientSecret = var.api_client_secret
  })

  # Runtime config, not baked into the image -- which is the only reason the
  # frontend could be cut over to the new zitadel app without rebuilding it.
  web_config = jsonencode({
    oidc = {
      clientId              = var.web_client_id
      redirectUri           = "https://score.wvl.app/"
      authorizationEndpoint = "https://auth.wvl.app/oauth/v2/authorize"
      tokenEndpoint         = "https://auth.wvl.app/oauth/v2/token"
      userInfoEndpoint      = "https://auth.wvl.app/oidc/v1/userinfo"
      healthzEndpoint       = "https://auth.wvl.app/auth/v1/healthz"
      rolesKey              = "urn:zitadel:iam:org:project:roles"
    }
    api = {
      baseUrl = "https://score-api.wvl.app"
    }
  })
}

resource "docker_image" "api" {
  name         = "wim07101993/score:${var.api_image_tag}"
  keep_locally = true
}

resource "docker_container" "api" {
  name    = "score-api"
  image   = docker_image.api.image_id
  restart = "unless-stopped"

  command = ["--config=/run/secrets/score_api_secrets"]

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  ports {
    internal = 7001
    external = var.api_port
  }

  # Was a compose `secret` read from /docker-volumes/score/ on bumba, edited by
  # hand. Now generated: the DSN carries a password tofu invented, and the
  # client id and secret come straight from the zitadel resources.
  upload {
    file    = "/run/secrets/score_api_secrets"
    content = local.api_secrets
  }

  networks_advanced {
    name    = var.traefik_network
    aliases = ["score-api"]
  }

  networks_advanced {
    name    = var.db_network
    aliases = ["score-api"]
  }

  depends_on = [postgresql_database.this]
}

# --- the frontend -------------------------------------------------------

resource "docker_image" "web" {
  name         = "wim07101993/score-frontend:${var.web_image_tag}"
  keep_locally = true
}

resource "docker_container" "web" {
  name    = "score-web-app"
  image   = docker_image.web.image_id
  restart = "unless-stopped"

  capabilities {
    drop = ["ALL"]
    add  = ["CAP_CHOWN", "CAP_SETGID", "CAP_SETUID"]
  }
  security_opts = ["no-new-privileges:true"]

  ports {
    internal = 80
    external = var.web_port
  }

  # Overwrites the config.json baked into the image.
  upload {
    file    = "/usr/share/nginx/html/config.json"
    content = local.web_config
  }

  networks_advanced {
    name    = var.traefik_network
    aliases = ["score-web-app"]
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:80/"]
    interval     = "1m0s"
    timeout      = "30s"
    retries      = 5
    start_period = "20s"
  }
}
