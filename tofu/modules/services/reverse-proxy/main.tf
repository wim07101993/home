# A traefik reverse proxy, one instance per host.
#
# Config lives HERE, beside the service it configures -- ./bumba/ and ./mindy/,
# each holding traefik.yml (static) and dynamic.yml (routes). `var.host` picks
# the directory. That keeps routing next to the thing it routes without
# duplicating sixty lines of container definition per host.
#
# This is a CUTOVER, not an adoption: a compose-created container carries
# com.docker.compose.* labels and a creation shape that docker_container cannot
# reproduce, so importing it would plan a recreate anyway. The portainer stack
# is deleted first -- leave it in place and its daily git redeploy fights tofu
# for the same container.
#
# Everything behind this proxy is down while it is not running: auth.wvl.app,
# score, partituren, and the dashboard.

resource "docker_image" "traefik" {
  name         = "traefik:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = var.container_name
  image   = docker_image.traefik.image_id
  restart = "unless-stopped"

  security_opts = ["no-new-privileges:true"]

  # Everything is in the two uploaded YAML files below. traefik reads
  # /etc/traefik/traefik.yml by default; naming it is one line against a class
  # of confusion about where config comes from.
  command = ["--configFile=/etc/traefik/traefik.yml"]


  ports {
    internal = 80
    external = 80
  }
  ports {
    internal = 443
    external = 443
  }

  volumes {
    host_path      = var.letsencrypt_path
    container_path = "/letsencrypt"
  }

  networks_advanced {
    name = var.network_name
  }

  # Static: entrypoints, providers, ACME. A real YAML file, read verbatim.
  upload {
    file    = "/etc/traefik/traefik.yml"
    content = file("${path.module}/${var.host}/traefik.yml")
  }

  # Dynamic: the routing table.
  #
  # Changing either file replaces the container -- a few seconds, and traefik
  # comes back with its certificates intact because acme.json lives in the bind
  # mount, not the container. If a route ever needs a tofu-managed value (an
  # OIDC client id, a generated password), the caller passes
  # templatefile(...) instead of file(...).
  # ASSEMBLED, not a file. Every route comes from the service that owns it --
  # see var.routing -- merged here with the one route the proxy owns itself.
  #
  # yamlencode cannot emit invalid YAML, which is worth something for a file
  # that, if malformed, takes every site on this host offline. What it also
  # cannot emit is COMMENTS: the history that used to live in dynamic.yml now
  # lives in each service's routing.tf, which is where it is read anyway.
  #
  # Changing any route replaces this container. That is new: a routing edit used
  # to touch one file on one module, and now depends on every service module.
  upload {
    file = "/etc/traefik/dynamic.yml"
    content = yamlencode({
      http = {
        routers = merge(
          {
            # entryPoints and tls are omitted deliberately: websecure is
            # asDefault and carries certResolver: le on both hosts, so every
            # router here inherits both. See ${var.host}/traefik.yml.
            dashboard = {
              rule    = "Host(`${var.dashboard_host}`)"
              service = "api@internal"
            }
          },
          merge([for r in var.routing : lookup(r, "routers", {})]...),
        )
        services    = merge([for r in var.routing : lookup(r, "services", {})]...)
        middlewares = merge([for r in var.routing : lookup(r, "middlewares", {})]...)
      }
    })
  }
}

# So service modules can depend on the network rather than naming it as a
# string -- which makes "created before traefik's network exists" impossible
# rather than merely unlikely.
# Echoes the input so existing consumers keep working; the network itself is
# ../../network now.
output "network_name" {
  value = var.network_name
}
