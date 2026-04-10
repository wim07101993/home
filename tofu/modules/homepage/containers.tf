resource "docker_service" "homepage" {
  name = "homepage"

  task_spec {
    container_spec {
      image = "ghcr.io/gethomepage/homepage:v1.12.3"
      env = {
        HOMEPAGE_ALLOWED_HOSTS = "wvl.app,homepage.wvl.app,100.127.106.121:3001"
        PUID                   = 1000
        PGID                   = 1000
      }

      mounts {
        type   = "bind"
        source = "/docker-volumes/homepage/config"
        target = "/app/config"
      }
      mounts {
        type   = "bind"
        source = "/docker-volumes/homepage/icons"
        target = "/app/public/icons"
      }
    }

    networks_advanced { name = var.traefik_network }
  }

  labels {
    label = "traefik.enable"
    value = "true"
  }
  labels {
    label = "traefik.http.routers.homepage.rule"
    value = "Host(`homepage.${var.domain}`)"
  }
  labels {
    label = "traefik.http.routers.homepage.entrypoints"
    value = "websecure"
  }
  labels {
    label = "traefik.http.routers.homepage.tls.certresolver"
    value = "le"
  }
}
