# renovate: datasource=docker depName=ghcr.io/twin/gatus
variable "image_tag" {
  type    = string
  default = "v5.36.0"
}

variable "traefik_network" {
  type = string
}

variable "data_path" {
  type        = string
  default     = "/docker-volumes/gatus/data"
  description = <<-EOT
    Holds the SQLite database: check results, uptime and past events.

    Create it before the first apply:

      ssh root@<bumba> mkdir -p /docker-volumes/gatus/data

    Less load-bearing than the same note on other modules: the gatus image is
    FROM scratch with no USER, so it runs as root and can write the root-owned
    directory docker would create for a missing bind source. Created explicitly
    anyway, so the path is deliberate rather than a side effect.
  EOT
}

variable "tailscale_ip" {
  type        = string
  description = <<-EOT
    Host address to publish the dashboard on, as an out-of-band route.

    Bound to bumba's tailscale address rather than 0.0.0.0 on purpose. A status
    page reachable only through traefik tells you nothing when traefik is what
    broke -- and that is not hypothetical, since every route on this host is in
    one file that replaces the container when it changes. Binding it publicly
    instead would put a second, unauthenticated front door on the box.
  EOT
}

variable "host_port" {
  type    = number
  default = 3009
}

variable "oidc_client_id" {
  type = string
}

variable "oidc_client_secret" {
  type      = string
  sensitive = true
}

# Sender and recipient are in config.yaml -- they are choices, and belong in
# the file that documents this deployment.
#
# The USERNAME is not a choice: it is the identity of a credential tofu creates
# in modules/mailgun. Duplicating it as a literal would let config.yaml and the
# real credential disagree, and the symptom of that is a silent SMTP auth
# failure -- alerts generated, never delivered, nothing on the dashboard wrong.
variable "smtp_username" {
  type = string
}

variable "smtp_password" {
  type      = string
  sensitive = true
}
