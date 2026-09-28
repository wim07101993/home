locals {
  routers     = merge([for x in var.routing : x.routers]...)
  services    = merge([for x in var.routing : x.services]...)
  middlewares = merge([for x in var.routing : x.middlewares]...)

  config_path = "/etc/traefik/traefik.yml"
}

resource "docker_image" "traefik" {
  name         = "traefik:v3.7.10"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = var.container_name
  image   = docker_image.traefik.image_id
  restart = "unless-stopped"

  security_opts = ["no-new-privileges:true"]

  command = ["--configFile=${local.config_path}"]

  ports {
    internal = 80
    external = 80
  }
  ports {
    internal = 443
    external = 443
  }

  volumes {
    host_path      = "/docker-volumes/traefik/letsencrypt"
    container_path = "/letsencrypt"
  }

  networks_advanced {
    name = "traefik-network"
  }

  upload {
    file    = local.config_path
    content = file("${path.module}/${var.host}/traefik.yml")
  }

  upload {
    file = "/etc/traefik/dynamic.yml"
    content = yamlencode({
      http = merge(length(local.middlewares) > 0 ? { middlewares = local.middlewares } : {}, {
        routers = merge(
          {
            dashboard = {
              rule    = "Host(`${var.dashboard_host}`)"
              service = "api@internal"
            }
          },
          {
            for name, r in local.routers :
            name => merge(
              { rule = r.rule, service = r.service },
              length(r.middlewares) > 0 ? { middlewares = r.middlewares } : {},
            )
          },
        )
        services = local.services
      })
    })
  }
}

output "network_name" {
  value = var.network_name
}
