resource "docker_image" "this" {
  name         = "plexinc/pms-docker:1.43.2.10687-563d026ea"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "plex"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  network_mode = "host"

  env = [
    "PUID=1000",
    "PGID=1000",
    "TZ=Etc/UTC",
    # Tells the image it is running under docker rather than as a bare install.
    # Reproduced from compose; the image behaves differently without it.
    "VERSION=docker",
  ]


  volumes {
    host_path      = "/docker-volumes/plex"
    container_path = "/config"
  }

  volumes {
    host_path      = "/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300/media"
    container_path = "/media"
  }
}
