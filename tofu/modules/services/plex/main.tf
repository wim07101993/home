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
  # identity and its claim. CAP_FOWNER is for usermod and groupmod, which
  # apply PLEX_UID/PLEX_GID; without it they fail and PMS quietly stays 1000.
  capabilities {
    drop = ["ALL"]
    add  = ["CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_FOWNER", "CAP_KILL", "CAP_SETGID", "CAP_SETUID"]
  }
  security_opts = ["no-new-privileges:true"]

  # Takes plex out of users (100), which can write to samson's shares. After a
  # restart gpasswd only reports that plex is no longer a member.
  entrypoint = ["/bin/sh", "-c", "gpasswd -d plex users; exec /init"]

  env = [
    # NixOS's id for plex; the image's default, 1000, is wim on this host.
    "PLEX_UID=193",
    "PLEX_GID=193",
    "TZ=Etc/UTC",
    # Tells the image it is running under docker rather than as a bare install.
    # Reproduced from compose; the image behaves differently without it.
    "VERSION=docker",
  ]


  volumes {
    host_path      = "/docker-volumes/plex"
    container_path = "/config"
  }

  # PMS reads the media as "other": files need a+r.
  volumes {
    host_path      = "/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300/media"
    container_path = "/media"
  }
}
