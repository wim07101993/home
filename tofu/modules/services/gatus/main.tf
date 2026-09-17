# status.wvl.app -- gatus on bumba.
#
# Exists because of the 2026-08 array incident and the kopia outage found
# during its recovery. Two independent failures ran for months because nothing
# in this estate reports its own health:
#
#   - the drive bay fan had not run for 5 months; found by opening the case
#   - kopia crash-looped for 5 weeks with no backups taken; found by reading
#     `docker ps` during an unrelated recovery
#
# Neither needed clever detection. A 60-second check would have caught both
# within minutes.
#
# On bumba rather than mindy, deliberately: a monitor that lives on the machine
# it is monitoring tells you nothing when that machine is the problem. bumba is
# also the box with out-of-band access via the Hetzner console.
#
# Gatus rather than uptime-kuma: the monitors are a YAML file in this repo
# instead of rows in a SQLite database behind a UI, so they are reviewable,
# diffable and restorable. Uptime-kuma ran here for a week with zero monitors
# configured -- the config being invisible is exactly how that goes unnoticed.

resource "random_password" "kopia_token" {
  length  = 40
  special = false
}

resource "docker_image" "this" {
  name         = "ghcr.io/twin/gatus:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "gatus"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  # bumba is a cpx11 with 2 GB of RAM, already running zitadel and postgres.
  # An unbounded monitoring tool on a 2 GB box can take down the things it is
  # meant to watch. memory_swap is docker's 2x default, stated explicitly --
  # see ../immich/main.tf for why omitting it never settles.
  memory      = 256
  memory_swap = 512

  security_opts = ["no-new-privileges:true"]

  # The secrets config.yaml references. Gatus expands ${VAR} from the
  # environment before parsing, which keeps these out of the file -- necessary,
  # because this repo is public. Non-secret settings stay in config.yaml.
  env = [
    "GATUS_OIDC_CLIENT_ID=${var.oidc_client_id}",
    "GATUS_OIDC_CLIENT_SECRET=${var.oidc_client_secret}",
    "GATUS_SMTP_USERNAME=${var.smtp_username}",
    "GATUS_SMTP_PASSWORD=${var.smtp_password}",
    "GATUS_KOPIA_TOKEN=${random_password.kopia_token.result}",
  ]

  # Reached by traefik over the shared network, and directly over tailscale so
  # the dashboard survives traefik being down. See var.tailscale_ip.
  ports {
    internal = 8080
    external = var.host_port
    ip       = var.tailscale_ip
  }

  mounts {
    type   = "bind"
    source = var.data_path
    target = "/data"
  }

  networks_advanced {
    name    = var.traefik_network
    aliases = ["gatus"]
  }

  # Gatus reads /config/config.yaml. Uploaded rather than bind-mounted: a bound
  # FILE (as opposed to its directory) does not reliably surface later edits to
  # the container, and editing it in place would put the running config out of
  # step with this repo anyway. Changing the file replaces the container, which
  # costs a few seconds and keeps history in the bind-mounted database.
  upload {
    file    = "/config/config.yaml"
    content = file("${path.module}/config.yaml")
  }
}

# For wiring kopia's post-snapshot push. Sensitive: it is a bearer token that
# lets the holder report backup success.
output "kopia_push_token" {
  value     = random_password.kopia_token.result
  sensitive = true
}

output "kopia_push_url" {
  value = "https://status.wvl.app/api/v1/endpoints/backups_kopia-mindy/external?success=true"
}
