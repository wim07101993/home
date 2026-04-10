resource "docker_service" "traefik" {
  name = "traefik"

  task_spec {
    container_spec {
      image = "traefik:v3.6.12"

      args = [
        "--log.level=DEBUG",
        "--api.dashboard=true",
        "--providers.docker=true",
        "--providers.docker.exposedbydefault=false",
        "--providers.docker.swarmmode=true",
        "--entrypoints.web.address=:80",
        "--entrypoints.web.http.redirections.entryPoint.to=websecure",
        "--entrypoints.web.http.redirections.entryPoint.scheme=https",
        "--entrypoints.websecure.address=:443",
        "--entrypoints.websecure.asDefault=true",
        "--entrypoints.websecure.http.tls.certResolver=le",
        "--certificatesresolvers.le.acme.httpchallenge=true",
        "--certificatesresolvers.le.acme.httpchallenge.entrypoint=web",
        "--certificatesresolvers.le.acme.email=wvl@wvl.app",
        "--certificatesresolvers.le.acme.storage=/letsencrypt/acme.json"
      ]

      mounts {
        type   = "bind"
        source = "/var/run/docker.sock"
        target = "/var/run/docker.sock"
        read_only = true
      }

      mounts {
        type   = "bind"
        source = "/docker-volumes/traefik/letsencrypt"
        target = "/letsencrypt"
      }
    }

    networks_advanced {
      name = var.network_id
    }
  }

  endpoint_spec {
    ports {
      target_port    = 80
      published_port = 80
      publish_mode   = "ingress"
    }
    ports {
      target_port    = 443
      published_port = 443
      publish_mode   = "ingress"
    }
  }

  labels {
    label = "traefik.enable"
    value = "true"
  }

  labels {
    label = "traefik.http.routers.dashboard.rule"
    value = "Host(`traefik.${var.domain}`)"
  }

  labels {
    label = "traefik.http.routers.dashboard.entrypoints"
    value = "websecure"
  }

  labels {
    label = "traefik.http.routers.dashboard.service"
    value = "api@internal"
  }

  labels {
    label = "traefik.http.routers.dashboard.tls.certresolver"
    value = "le"
  }
}
