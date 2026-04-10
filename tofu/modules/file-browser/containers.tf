resource "docker_service" "filebrowser" {
  name = "filebrowser"

  task_spec {
    container_spec {
      image = "gtstef/filebrowser:1.2.4-stable-slim"

      env = {
        FILEBROWSER_CONFIG = "/run/secrets/filebrowser_config"
      }

      secrets {
        secret_id   = docker_secret.filebrowser_config.id
        secret_name = docker_secret.filebrowser_config.name
        file_name   = "filebrowser_config"
      }

      mounts {
        type   = "bind"
        source = "/docker-volumes/filebrowser/config"
        target = "/home/filebrowser/data"
      }
      mounts {
        type   = "bind"
        source = "/docker-volumes/filebrowser/files"
        target = "/files"
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
    label = "traefik.http.routers.drive.rule"
    value = "Host(`drive.${var.domain}`)"
  }
  labels {
    label = "traefik.http.routers.drive.entrypoints"
    value = "websecure"
  }
  labels {
    label = "traefik.http.routers.drive.tls.certresolver"
    value = "le"
  }
}
