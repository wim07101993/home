resource "docker_service" "zitadel" {
  name = "zitadel"

  task_spec {
    container_spec {
      image = "ghcr.io/zitadel/zitadel:latest"
      command = [
        "start-from-init",
        "--config=/run/secrets/zitadel_config",
        "--config=/run/secrets/zitadel_secrets",
        "--steps=/run/secrets/zitadel_init_steps",
        "--masterkeyFile=/run/secrets/zitadel_masterkey"
      ]

      secrets {
        secret_id   = docker_secret.zitadel_config.id
        secret_name = docker_secret.zitadel_config.name
        file_name   = "zitadel_config"
      }
      secrets {
        secret_id   = docker_secret.zitadel_secrets.id
        secret_name = docker_secret.zitadel_secrets.name
        file_name   = "zitadel_secrets"
      }
      secrets {
        secret_id   = docker_secret.zitadel_init_steps.id
        secret_name = docker_secret.zitadel_init_steps.name
        file_name   = "zitadel_init_steps"
      }
      secrets {
        secret_id   = docker_secret.zitadel_masterkey.id
        secret_name = docker_secret.zitadel_masterkey.name
        file_name   = "zitadel_masterkey"
      }

      mounts {
        type   = "bind"
        source = "/docker-volumes/zitadel/login-client"
        target = "/login-client"
      }
    }

    networks_advanced { name = var.traefik_network }
    networks_advanced { name = var.db_network }
  }

  labels {
    label = "traefik.enable"
    value = "true"
  }
  labels {
    label = "traefik.http.routers.zitadel.rule"
    value = "Host(`auth.${var.domain}`) && !PathPrefix(`/ui/v2/login`)"
  }
  labels {
    label = "traefik.http.routers.zitadel.entrypoints"
    value = "websecure"
  }
  labels {
    label = "traefik.http.routers.zitadel.tls.certresolver"
    value = "le"
  }
}

resource "docker_service" "zitadel_login" {
  name = "zitadel-login"

  task_spec {
    container_spec {
      image = "ghcr.io/zitadel/zitadel-login:latest"
      env = {
        ZITADEL_API_URL               = "http://zitadel:8080"
        NEXT_PUBLIC_BASE_PATH         = "/ui/v2/login"
        ZITADEL_SERVICE_USER_TOKEN_FILE = "/login-client/login-client.pat"
        CUSTOM_REQUEST_HEADERS        = "Host:auth.${var.domain}"
      }

      mounts {
        type   = "bind"
        source = "/docker-volumes/zitadel/login-client"
        target = "/login-client"
        read_only = true
      }
    }

    networks_advanced { name = var.traefik_network }
    # Needs to talk to zitadel, but they share traefik_network? 
    # Original used zitadel-network. Let's add an internal network.
  }

  labels {
    label = "traefik.enable"
    value = "true"
  }
  labels {
    label = "traefik.http.routers.zitadel-login.rule"
    value = "Host(`auth.${var.domain}`) && PathPrefix(`/ui/v2/login`)"
  }
  labels {
    label = "traefik.http.routers.zitadel-login.entrypoints"
    value = "websecure"
  }
  labels {
    label = "traefik.http.routers.zitadel-login.tls.certresolver"
    value = "le"
  }
}
