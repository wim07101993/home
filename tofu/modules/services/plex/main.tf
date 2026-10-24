resource "docker_image" "this" {
  name         = "plexinc/pms-docker:1.43.5.11029-6bf8af3f0"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "plex"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  network_mode = "host"
  userns_mode  = "host"

  # CAP_DAC_OVERRIDE is load-bearing. With userns_mode = "host" the image's files
  # belong to 165536, not root, and s6 does not start unless root can write to
  # them. It also lets the first-run script see Preferences.xml as root; if it
  # cannot, it writes an empty one over the real file: the server loses its
  # identity and its claim.
  capabilities {
    drop = ["ALL"]
    add  = ["CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_KILL", "CAP_SETGID", "CAP_SETUID"]
  }
  security_opts = ["no-new-privileges:true"]

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
