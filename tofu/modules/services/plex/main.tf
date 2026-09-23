# plex on samson. The media server, and the only service on the array host
# other than the backup tooling.
#
# A CUTOVER, not an import: the container carries com.docker.compose.* labels
# from a Portainer stack, and docker_container cannot reproduce those. The
# stack must be DELETED IN PORTAINER FIRST -- see README.md. Leave it and the
# two systems fight over one container name, which is the 2026-08 incident.
#
# network_mode = "host", inherited from compose and not negotiable: Plex's
# client discovery uses GDM broadcasts on 32410-32414/udp and DLNA on 1900/udp,
# none of which survive a bridge. The published 32400 is a consequence of host
# mode, not a `ports` block.
resource "docker_image" "this" {
  name         = "plexinc/pms-docker:${var.image_tag}"
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

  # Samson's dockerd sets these daemon-wide. Omitting them is not "no opinion":
  # the provider reads the live values back and plans a replacement on every
  # apply. Same as the other two containers on this host.
  log_opts = {
    "max-file" = "3"
    "max-size" = "50m"
  }

  volumes {
    host_path      = var.config_path
    container_path = "/config"
  }

  volumes {
    host_path      = var.media_path
    container_path = "/media"
  }

  # NOT DECLARED: /transcode. The image declares it as a VOLUME, so docker
  # creates an anonymous one and the live container has it. Naming it here
  # would be a new, empty volume on every replacement -- which is harmless for
  # scratch transcode data, but it would also be a difference from the compose
  # deployment for no reason.
  #
  # NO security_opts, unlike every other module here. The live container has
  # none and this is a cutover, so it goes across like-for-like; adding
  # no-new-privileges is a separate change that should be made on its own and
  # verified, not smuggled into a migration where a failure would be ambiguous.
  #
  # It is probably safe -- the entrypoint chowns /config as root and then drops
  # to PUID/PGID, and no-new-privileges blocks setuid escalation rather than
  # anything root already does -- but "probably" is not a reason to bundle it.
}
