# bumba's reverse proxy. Cut over from the compose stack `reverse-proxy` on
# 2026-09-16.
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

  # Vestigial, and kept on purpose. Compose created this network and stamped
  # these on it; dropping them FORCES REPLACEMENT, and replacing the network
  # every service on bumba is attached to is not something to do as a side
  # effect of an import. prevent_destroy caught exactly that on 2026-09-16.
  #
  # The config-hash in particular is a lie the moment compose stops managing
  # this -- it is compose's hash of a definition that no longer governs. It
  # stays anyway, because "matches reality" beats "reads nicely" for an
  # adopted resource. Removing them later is a deliberate, scheduled
  # replacement, not a tidy-up.
  labels {
    label = "com.docker.compose.config-hash"
    value = "269096a0575268b819c342ef4a1d6d6c8240ce7cd8ddfb507530a7587d85e957"
  }
  labels {
    label = "com.docker.compose.network"
    value = "reverse-proxy-network"
  }
  labels {
    label = "com.docker.compose.project"
    value = "reverse-proxy"
  }
  labels {
    label = "com.docker.compose.version"
    value = ""
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
  name    = "reverse-proxy"
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
    content = file("${path.module}/traefik.yml")
  }

  # Dynamic: the routing table. Also a real YAML file.
  #
  # Changing either file replaces the container -- a few seconds, and traefik
  # comes back with its certificates intact because acme.json lives in the bind
  # mount, not the container. If a route ever needs a tofu-managed value (an
  # OIDC client id, a generated password), switch this to
  # templatefile("${path.module}/dynamic.yml.tftpl", { ... }).
  upload {
    file    = "/etc/traefik/dynamic.yml"
    content = file("${path.module}/dynamic.yml")
  }
}
