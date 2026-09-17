# it-tools.wvl.app -- a static nginx site of developer utilities.
#
# The cheapest possible cutover: no database, no OIDC client, no secrets, no
# volumes. If anything about the container migration pattern is wrong, this is
# where it shows up harmlessly.

resource "docker_image" "this" {
  name         = "corentinth/it-tools:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "it-tools"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  # Reproduced from the compose stack. The image runs nginx, which wants these
  # three to drop privileges after binding; everything else is dropped.
  capabilities {
    drop = ["ALL"]
    add  = ["CHOWN", "SETGID", "SETUID"]
  }
  security_opts = ["no-new-privileges:true"]

  # LOST IN TRANSLATION: the compose stack set
  # `deploy.resources.limits.pids: 99`. kreuzwerker/docker has no equivalent --
  # the schema has `ulimit` blocks but no pids_limit, and PidsLimit is not
  # exposed at all (v3.9.0).
  #
  # Do NOT substitute `ulimit { name = "nproc" }`. That is an rlimit, enforced
  # per UID across the whole host rather than per container, so with containers
  # sharing a UID it would either do nothing or throttle an unrelated one. It
  # looks equivalent and is worse than nothing.
  #
  # This is a genuine capability regression from compose, and it applies to
  # every stack using that limit -- zitadel, zitadel-login and both score
  # services all set pids: 99 and will hit the same wall. `memory` and
  # `memory_swap` are the levers the provider does offer, but they constrain a
  # different failure.

  ports {
    internal = 80
    external = var.host_port
  }

  # Only traefik's network.
  #
  # Compose also created `it-tools_it-tools-network` -- a private bridge with
  # exactly one container on it and no peers to talk to. That is an artifact of
  # compose's per-project model, not a feature, so it is not reproduced. It
  # will be left orphaned by the cutover and can be removed.
  networks_advanced {
    name    = var.network_name
    aliases = ["it-tools"]
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:80"]
    interval     = "60s"
    timeout      = "30s"
    retries      = 5
    start_period = "20s"
  }
}
