locals {
  home = "/ftp/${var.user}"
}

# vsftpd's USERS format splits on spaces and `|`, so neither may appear.
resource "random_password" "this" {
  length  = 24
  special = false
}

resource "docker_image" "this" {
  name         = "delfer/alpine-ftp-server@sha256:3ad587aa1b0822a54e3f570fdcd87e2c2a2c5b27537b2780d97f1284b6872914"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "ftp"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  network_mode = "host"
  userns_mode  = "host"

  entrypoint = [
    "/sbin/tini", "--", "/bin/sh", "-c",
    "chown root:root /etc/vsftpd/vsftpd.conf && exec /bin/start_vsftpd.sh",
  ]

  env = [
    "USERS=${var.user}|${random_password.this.result}|${local.home}|${var.uid}|${var.gid}",
    "MIN_PORT=${var.passive_ports.from}",
    "MAX_PORT=${var.passive_ports.to}",
  ]

  mounts {
    type   = "bind"
    source = var.media_path
    target = "${local.home}/media"
  }
}
