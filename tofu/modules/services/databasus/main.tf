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

# ---------------------------------------------------------------- checker ---
# Pushes the state of each dump to gatus. See check-backups.sh for why this
# reads the directory instead of asking databasus.
#
# It lives here rather than in its own module because it is inseparable from
# the thing above it: same host, same bind mount, and the floors in
# var.monitored are only meaningful next to the service that produces the
# files.
resource "docker_image" "checker" {
  name         = "curlimages/curl:${var.checker_image_tag}"
  keep_locally = true
}

resource "docker_container" "checker" {
  name    = "databasus-backup-check"
  image   = docker_image.checker.image_id
  restart = "unless-stopped"

  # The image's ENTRYPOINT is `curl` itself, so running anything else means
  # replacing it rather than passing a command.
  entrypoint = ["/bin/sh", "/check-backups.sh"]

  # Tiny by construction: a shell loop and one curl per database per hour.
  memory      = 32
  memory_swap = 64

  security_opts = ["no-new-privileges:true"]

  # Samson's dockerd sets these daemon-wide, so omitting them is not "no
  # opinion" -- the provider reads the live values back and plans a replacement
  # on every apply. Same reason they are pinned on the container above.
  log_opts = {
    "max-file" = "3"
    "max-size" = "50m"
  }

  env = [
    "CHECKS=${join(" ", [for k, m in var.monitored : "${k}:${m.prefix}:${m.min_bytes}"])}",
    "GATUS_BASE=${var.gatus_base_url}",
    "GATUS_TOKEN=${var.gatus_token}",
    "MAX_AGE=${var.max_age_seconds}",
    "INTERVAL=${var.check_interval_seconds}",
  ]

  # READ-ONLY, and the only thing this container can see. A checker that can
  # write to the backups it validates is a checker that can be the reason they
  # are wrong.
  mounts {
    type      = "bind"
    source    = "${var.data_path}/backups"
    target    = "/backups"
    read_only = true
  }

  # No networks_advanced: the default bridge reaches status.wvl.app over the
  # public internet, which is also what makes this an independent signal --
  # it does not share a path with anything it is reporting on.

  upload {
    file    = "/check-backups.sh"
    content = file("${path.module}/check-backups.sh")
  }
}
