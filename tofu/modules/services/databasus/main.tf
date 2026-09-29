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
  mounts {
    type   = "bind"
    source = "/export/backups/backup-server/databasus/data/backups"
    target = "/databasus-data/backups"
  }
}
