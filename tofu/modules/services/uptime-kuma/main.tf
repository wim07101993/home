# status.wvl.app -- uptime-kuma on bumba.
#
# Exists because of the 2026-08 array incident and the kopia outage found
# during its recovery. Two independent failures ran for months because nothing
# in this estate reports its own health:
#
#   - the drive bay fan had not run for 5 months; found by opening the case
#   - kopia crash-looped for 5 weeks with no backups taken; found by reading
#     `docker ps` during an unrelated recovery
#
# Neither needed clever detection. A 60-second HTTP check would have caught
# both within minutes. And as of today kopia on mindy has been stopped for four
# days -- the same failure, again, still found by hand.
#
# On bumba rather than mindy, deliberately: a monitor that lives on the machine
# it is monitoring tells you nothing when that machine is the problem. bumba is
# also the box with out-of-band access via the Hetzner console.

resource "docker_image" "this" {
  name         = "louislam/uptime-kuma:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "uptime-kuma"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  # bumba is a cpx11 with 2 GB of RAM, already running zitadel and postgres.
  # The compose stack this was written from set no limit; one is added here
  # because an unbounded monitoring tool on a 2 GB box can take down the things
  # it is meant to watch. memory_swap is docker's 2x default, stated
  # explicitly -- see ../immich/main.tf for why omitting it never settles.
  memory      = 512
  memory_swap = 1024

  security_opts = ["no-new-privileges:true"]

  ports {
    internal = 3001
    external = var.host_port
  }

  mounts {
    type   = "bind"
    source = var.data_path
    target = "/app/data"
  }

  networks_advanced {
    name    = var.traefik_network
    aliases = ["uptime-kuma"]
  }
}
