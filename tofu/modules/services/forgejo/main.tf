locals {
  data_path = "/docker-volumes/forgejo"
}

# AUTHORITATIVE: start.sh sets wim's password to this on every start, so a
# password changed in the UI is reset by the next restart.
resource "random_password" "admin" {
  length  = 32
  special = false
}

resource "docker_image" "this" {
  name         = "codeberg.org/forgejo/forgejo:17.0.1-rootless"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "forgejo"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  env = [
    "ADMIN_PASSWORD=${random_password.admin.result}",

    # app.ini is written from these on every start. INSTALL_LOCK skips the
    # web installer, which would otherwise hand the first visitor the setup.
    "FORGEJO__security__INSTALL_LOCK=true",
    "FORGEJO__server__ROOT_URL=http://${var.tailscale_ip}:${var.host_port}/",
    "FORGEJO__server__DISABLE_SSH=true",
    "FORGEJO__server__START_SSH_SERVER=false",
    "FORGEJO__service__DISABLE_REGISTRATION=true",

    # No runner anywhere.
    "FORGEJO__actions__ENABLED=false",
  ]

  command = ["sh", "-c", file("${path.module}/start.sh")]

  ports {
    internal = 3000
    external = var.host_port
    ip       = var.tailscale_ip
  }

  volumes {
    host_path      = local.data_path
    container_path = "/var/lib/gitea"
  }

  healthcheck {
    test = ["CMD", "curl", "-f", "http://localhost:3000/api/healthz"]

    interval     = "1m0s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }
}
