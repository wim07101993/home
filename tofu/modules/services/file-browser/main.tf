# drive.wvl.app -- file-browser, on mindy.
#
# Serves nine NFS shares from samson, plus the 2 GB upload limit applied by the
# `drive-size-limit` middleware in the reverse-proxy module's mindy/dynamic.yml.

resource "docker_image" "this" {
  name         = "gtstef/filebrowser:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "filebrowser"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  env = ["FILEBROWSER_CONFIG=/home/filebrowser/data/config.yaml"]

  ports {
    internal = 80
    external = var.host_port
  }

  mounts {
    type   = "bind"
    source = var.config_path
    target = "/home/filebrowser/data"
  }

  # THE rslave PROPAGATION IS LOAD-BEARING, and its absence does not error.
  #
  # var.files_path holds nine x-systemd.automount NFS mounts from samson. Those
  # are established LAZILY, on first access -- which is after this container
  # starts. With docker's default (private) propagation the container keeps the
  # empty pre-mount view forever and serves empty directories, cheerfully, with
  # no error anywhere.
  #
  # `mounts` rather than `volumes` purely because `volumes` has no propagation
  # option.
  mounts {
    type   = "bind"
    source = var.files_path
    target = "/files"

    bind_options {
      propagation = "rslave"
    }
  }

  # The document shares, from the local volume rather than from samson.
  # See var.documents_path. `audio`, `audio-archive`, `media` and `backups`
  # still arrive over NFS through the parent bind above -- audio is 55.4 GB and
  # does not fit on rafiki yet.
  dynamic "mounts" {
    for_each = var.document_shares
    content {
      type   = "bind"
      source = "${var.documents_path}/${mounts.value}"
      target = "/files/${mounts.value}"
    }
  }

  networks_advanced {
    name = var.traefik_network
  }

  # mindy's postgres.
  networks_advanced {
    name = var.db_network
  }

  # Compose also made `filebrowser_filebrowser-network` -- one container, no
  # peers. Not reproduced; left orphaned by the cutover and removable.
}
