# databasus -- the database backup tool, on samson.
#
# It dumps the postgres databases on bumba and mindy on a schedule. That makes
# it the one container whose silent failure is invisible until the moment it
# matters, which is the argument for having it in code at all.
#
# A CUTOVER, not an import. The compose stack must be removed from portainer on
# samson FIRST -- see README.md. Two systems managing one container is how the
# 2026-08 incident happened.
resource "docker_image" "this" {
  name         = "databasus/databasus:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "databasus"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  # Inherited from the compose stack. Not cosmetic: without these the container
  # is REPLACED on every apply, because docker reports the live values and the
  # config says none. A perpetual one-resource diff trains you to skim plans,
  # which is how a real change gets approved by reflex.
  log_opts = {
    "max-file" = "3"
    "max-size" = "50m"
  }

  ports {
    internal = 4005
    external = var.host_port
  }

  # A bind, not a named volume: the compose stack used a bind and the 2026-08
  # backup audit found databasus's data under /docker-volumes accordingly.
  # Switching to a named volume here would start it empty -- new container, new
  # volume, no schedules, no error.
  mounts {
    type   = "bind"
    source = var.data_path
    target = "/databasus-data"
  }

  # No networks_advanced: samson runs no reverse proxy, so this stays on the
  # default bridge exactly as compose left it. The published port above is the
  # access path.

  # NOT REPRODUCED FROM COMPOSE: nothing. The stack was four lines -- image,
  # restart, one port, one volume. That is why this is the right first thing to
  # move on samson, for the same reason it-tools was on mindy.
}
