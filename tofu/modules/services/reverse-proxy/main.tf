locals {
  routers     = merge([for x in var.routing : x.routers]...)
  services    = merge([for x in var.routing : x.services]...)
  middlewares = merge([for x in var.routing : x.middlewares]...)

  config_path = "/etc/traefik/traefik.yml"
}

resource "random_password" "dashboard" {
  length  = 32
  special = false
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
    external = var.http_port
  }
  ports {
    internal = 443
    external = var.https_port
  }

  volumes {
    host_path      = "/docker-volumes/traefik/letsencrypt"
    container_path = "/letsencrypt"
  }

  networks_advanced {
    name = var.network_name
  }

  upload {
    file    = local.config_path
    content = file("${path.module}/${var.host}/traefik.yml")
  }

  upload {
    file = "/etc/traefik/dynamic.yml"
    content = yamlencode({
      http = {
        # nonsensitive: a bcrypt hash of a 32-character random password is safe
        # to show, and keeping it visible keeps routing changes readable in plans.
        middlewares = merge(local.middlewares, {
          "dashboard-auth" = {
            basicAuth = { users = ["admin:${nonsensitive(random_password.dashboard.bcrypt_hash)}"] }
          }
        })
        routers = merge(
          {
            dashboard = {
              rule        = "Host(`${var.dashboard_host}`)"
              service     = "api@internal"
              middlewares = ["dashboard-auth"]
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
      }
    })
  }
}

