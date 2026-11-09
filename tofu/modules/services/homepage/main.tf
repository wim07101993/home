resource "docker_image" "this" {
  name         = "ghcr.io/gethomepage/homepage:v2.7.0"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "homepage"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  env = [
    "HOMEPAGE_ALLOWED_HOSTS=wvl.app,homepage.wvl.app,100.127.106.121:3001",
    "LOG_TARGETS=stdout",
  ]

  user = "1000:1000"

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  ports {
    internal = 3000
    external = var.host_port
  }

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
    name = docker_network.traefik.name
  }
}

# Shared with traefik and nothing else.
resource "docker_network" "traefik" {
  name       = "traefik-homepage"
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false
}
