# homepage.wvl.app -- the dashboard, on mindy.

resource "docker_image" "this" {
  name         = "ghcr.io/gethomepage/homepage:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "homepage"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  env = [
    "HOMEPAGE_ALLOWED_HOSTS=${var.allowed_hosts}",
    "PUID=1000",
    "PGID=1000",
  ]

  # CAP_ prefixes required -- docker stores the canonical form and capabilities
  # force replacement, so the bare names recreate the container on every apply.
  capabilities {
    drop = ["ALL"]
    add  = ["CAP_SETGID", "CAP_SETUID"]
  }
  security_opts = ["no-new-privileges:true"]

  # `pids: 99` from the compose stack is not reproducible -- see
  # ../it-tools/main.tf.

  ports {
    internal = 3000
    external = var.host_port
  }

  # Config and icons are UPLOADED from this module, not bind-mounted from
  # /docker-volumes/homepage on mindy.
  #
  # The bind mount is what let the two drift: the repo held a copy nobody had
  # to sync, and by 2026-09-17 it listed Memo under Bumba, was missing Keuken
  # entirely, and lacked seven files the host had. Uploading makes this
  # directory the source of truth -- edit here, apply, done.
  #
  # `source` rather than `content`: the provider reads the file at apply time
  # and stores a hash, so `tofu plan` stays readable. `content` would embed
  # every file in state AND print it in the diff, including a 244 KB SVG.
  #
  # Changing any file replaces the container. For a dashboard that is a few
  # seconds.
  dynamic "upload" {
    for_each = fileset("${path.module}/config", "*")
    content {
      file        = "/app/config/${upload.value}"
      source      = "${path.module}/config/${upload.value}"
      source_hash = filesha256("${path.module}/config/${upload.value}")
    }
  }

  dynamic "upload" {
    for_each = fileset("${path.module}/icons", "*.svg")
    content {
      file        = "/app/public/icons/${upload.value}"
      source      = "${path.module}/icons/${upload.value}"
      source_hash = filesha256("${path.module}/icons/${upload.value}")
    }
  }

  networks_advanced {
    name = var.traefik_network
  }

  # Compose also made `homepage_homepage-network` -- one container, no peers.
  # Not reproduced.
}
