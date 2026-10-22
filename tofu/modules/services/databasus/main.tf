resource "docker_image" "this" {
  name         = "databasus/databasus:v3.51.0"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "databasus"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  ports {
    internal = 4005
    external = var.host_port
  }

  mounts {
    type   = "bind"
    source = "/docker-volumes/backup-server/databasus/data"
    target = "/databasus-data"
  }

  # The dumps go to the array's backups subvolume, not the OS disk. Named directly:
  # data/backups on the OS disk is only a symlink to here, which docker would
  # resolve but which nothing else records. pgdata itself stays on the OS disk:
  # the image never shuts postgres down cleanly, and crash recovery on the
  # array's disks outlasts its startup wait, after which it runs pg_resetwal.
  mounts {
    type   = "bind"
    source = "/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300/backups/backup-server/databasus/data/backups"
    target = "/databasus-data/backups"
  }
}
