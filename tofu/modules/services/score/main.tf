# --- the API ------------------------------------------------------------

locals {
  api_secrets = jsonencode({
    dbConnectionString = join(" ", [
      "user=${postgresql_role.this.name}",
      "password=${random_password.db.result}",
      "host=db",
      "port=5432",
      "dbname=${postgresql_database.this.name}",
      "sslmode=disable",
    ])

    tokenIntrospectionUrl          = "https://auth.wvl.app/oauth/v2/introspect"
    userInfoUrl                    = "https://auth.wvl.app/oidc/v1/userinfo"
    rolesKey                       = "urn:zitadel:iam:org:project:roles"
    tokenIntrospectionClientId     = zitadel_application_api.api.client_id
    tokenIntrospectionClientSecret = zitadel_application_api.api.client_secret
  })

  web_config = jsonencode({
    oidc = {
      clientId              = zitadel_application_oidc.web.client_id
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
  name         = "wim07101993/score:v0.6.0"
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
    external = 7001
  }

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
}

# --- the frontend -------------------------------------------------------

resource "docker_image" "web" {
  name         = "wim07101993/score-frontend:v0.6.0"
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
    external = 3006
  }

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
