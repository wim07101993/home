locals {
  data_path     = "/docker-volumes/arcane/data"
  projects_path = "/docker-volumes/arcane/projects"
}

resource "random_password" "encryption_key" {
  length  = 32
  special = false
}

resource "docker_image" "this" {
  name         = "ghcr.io/getarcaneapp/manager:v2.17.3"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "arcane"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  # The docker socket is root's on the host, which a remapped container cannot
  # open. 951 is the arcane account in nix/hosts/plop/default.nix, 131 the
  # docker group.
  userns_mode = "host"
  user        = "951:951"
  group_add   = ["131"]

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  # A killed arcane leaves its actor registration behind, and the next start
  # waits a minute and a half for it to expire. Stopped, it deregisters.
  stop_timeout = 15

  env = [
    "TZ=Europe/Brussels",
    "APP_URL=http://${var.tailscale_ip}:${var.host_port}",
    "ENCRYPTION_KEY=${random_password.encryption_key.result}",
    "PROJECTS_DIRECTORY=${local.projects_path}",
    "ANALYTICS_DISABLED=true",

    # Versions come from renovate. An upgrade from the UI would replace the
    # container behind tofu's back.
    "UPDATE_CHECK_DISABLED=true",

    # Every setting from here, none from the UI. That is what lets tofu turn
    # off local login, and with it the default arcane / arcane-admin account.
    "UI_CONFIGURATION_DISABLED=true",
    "AUTH_LOCAL_ENABLED=false",

    "OIDC_ENABLED=true",
    "OIDC_ISSUER_URL=${var.oidc_issuer_url}",
    "OIDC_CLIENT_ID=${zitadel_application_oidc.this.client_id}",
    "OIDC_CLIENT_SECRET=${zitadel_application_oidc.this.client_secret}",
    "OIDC_PROVIDER_NAME=Home",
    "OIDC_AUTO_REDIRECT_TO_PROVIDER=true",

    # Zitadel decides who gets in (see auth.tf), so everyone who does is admin.
    # Arcane only reads groups from a list or a string, and zitadel's roles
    # claim is an object, so the mapping matches the issuer, which every token
    # from zitadel carries.
    "OIDC_GROUPS_CLAIM=iss",
    "OIDC_ROLE_MAPPINGS=${jsonencode([{ claimValue = var.oidc_issuer_url, roleId = "role_admin" }])}",
  ]

  ports {
    internal = 3552
    external = var.host_port
    ip       = var.tailscale_ip
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

  volumes {
    host_path      = local.data_path
    container_path = "/app/data"
  }

  volumes {
    host_path      = local.projects_path
    container_path = local.projects_path
  }

  healthcheck {
    test = ["CMD", "./arcane", "health", "--timeout", "2s"]

    interval     = "1m0s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }
}
