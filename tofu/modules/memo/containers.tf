resource "docker_service" "memo" {
  name = "memo"

  task_spec {
    container_spec {
      image = "neosmemo/memos:0.26.2"

      env = {
        MEMOS_DRIVER   = "postgres"
        MEMOS_DSN_FILE = "/run/secrets/db_connection_string"
      }

      secrets {
        secret_id   = docker_secret.memo_db_dsn.id
        secret_name = docker_secret.memo_db_dsn.name
        file_name   = "db_connection_string"
      }
    }

    networks_advanced {
      name = var.traefik_network
    }
    networks_advanced {
      name = var.db_network
    }
  }

  labels {
    label = "traefik.enable"
    value = "true"
  }

  labels {
    label = "traefik.docker.network"
    value = var.traefik_network
  }

  labels {
    label = "traefik.http.routers.memo.rule"
    value = "Host(`memo.${var.domain}`)"
  }

  labels {
    label = "traefik.http.routers.memo.entrypoints"
    value = "websecure"
  }

  labels {
    label = "traefik.http.routers.memo.tls.certresolver"
    value = "le"
  }
}
