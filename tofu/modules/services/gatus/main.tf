resource "random_password" "databasus_token" {
  length  = 40
  special = false
}

resource "random_password" "backrest_token" {
  length  = 40
  special = false
}

resource "docker_image" "this" {
  name         = "ghcr.io/twin/gatus:v5.36.0"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "gatus"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  memory      = 256
  memory_swap = 512

  security_opts = ["no-new-privileges:true"]

  env = [
    "GATUS_OIDC_CLIENT_ID=${zitadel_application_oidc.this.client_id}",
    "GATUS_OIDC_CLIENT_SECRET=${zitadel_application_oidc.this.client_secret}",
    "GATUS_SMTP_USERNAME=${mailgun_domain_credential.smtp.login}@${var.mail_domain}",
    "GATUS_SMTP_PASSWORD=${random_password.smtp.result}",
    "GATUS_DATABASUS_TOKEN=${random_password.databasus_token.result}",
    "GATUS_BACKREST_TOKEN=${random_password.backrest_token.result}",
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

# Consumed by ../databasus, which runs the checker on samson. Passing the token
# through the graph rather than copying it by hand is what keeps the two sides
# from drifting: rotating it here restarts both containers.
output "databasus_push_token" {
  value     = random_password.databasus_token.result
  sensitive = true
}

# Consumed by ../backrest on both mindy and samson. One token for both
# instances -- they are pushed by processes on different hosts, but anything
# able to read one config.json is already on a host that holds a repository
# password, so per-host tokens would divide nothing.
output "backrest_push_token" {
  value     = random_password.backrest_token.result
  sensitive = true
}

# The checker appends "/backups_databasus-<key>/external?success=<bool>". The
# keys come from var.monitored there and must match the external-endpoints in
# config.yaml here. Nothing enforces that match -- a typo on either side reads
# as a permanently-down endpoint, which is at least the safe direction to fail.
output "external_endpoint_base_url" {
  value = "https://status.wvl.app/api/v1/endpoints"
}
