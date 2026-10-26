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

  # Host network, so ports 21 and 20 need NET_BIND_SERVICE. SYS_CHROOT is for
  # vsftpd's own unprivileged helper; the users are not chrooted. DAC_OVERRIDE
  # because with userns_mode = "host" the image's files belong to 165536, not
  # root, and the start script writes /etc/passwd and /etc/shadow.
  capabilities {
    drop = ["ALL"]
    add  = ["CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_NET_BIND_SERVICE", "CAP_SETGID", "CAP_SETUID", "CAP_SYS_CHROOT"]
  }
  security_opts = ["no-new-privileges:true"]

  entrypoint = [
    "/sbin/tini", "--", "/bin/sh", "-c",
    # umask 002 so wim, through the media group, can change what is uploaded.
    "chown root:root /etc/vsftpd/vsftpd.conf && sed -i 's/^local_umask=.*/local_umask=002/' /etc/vsftpd/vsftpd.conf && exec /bin/start_vsftpd.sh",
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

  mounts {
    type   = "bind"
    source = var.audio_archive_path
    target = "${local.home}/audio-archive"
  }
}
