resource "docker_service" "filebrowser" {
  name = "filebrowser"

  task_spec {
    container_spec {
      image = "gtstef/filebrowser:1.2.4-stable-slim"

      env = {
        FILEBROWSER_CONFIG = "/home/filebrowser/data/config.yaml"
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
