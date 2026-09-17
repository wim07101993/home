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

resource "docker_network" "this" {
  name       = var.network_name
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false

  # Whatever compose stamped on this network when it created it. Vestigial,
  # and reproduced on purpose: dropping a label FORCES REPLACEMENT, and
  # replacing the network every service on the host is attached to is not
  # something to do as a side effect of an import. prevent_destroy caught
  # exactly that on bumba, 2026-09-16.
  #
  # Per host, because they differ -- the project name and config-hash belong to
  # that host's compose stack. They were briefly hardcoded to bumba's values,
  # which would have stamped mindy's network with the wrong project.
  dynamic "labels" {
    for_each = var.network_labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  lifecycle {
    # zitadel and score are still compose-managed and attach to this by name.
    # Destroying it detaches them with no warning.
    prevent_destroy = true
  }
}

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
    name = docker_network.this.name
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
  upload {
    file    = "/etc/traefik/dynamic.yml"
    content = file("${path.module}/${var.host}/dynamic.yml")
  }
}
