# renovate: datasource=docker depName=ghcr.io/gethomepage/homepage
variable "image_tag" {
  type    = string
  default = "v2.2.0"
}

variable "traefik_network" {
  type = string
}

variable "allowed_hosts" {
  type        = string
  default     = "wvl.app,homepage.wvl.app,100.127.106.121:3001"
  description = <<-EOT
    homepage v2 refuses requests whose Host header is not listed here, so a
    missing entry is a blank page rather than an error.

    `wvl.app` is in there and is bumba's traefik dashboard, not this -- probably
    vestigial. Left alone: removing it is a behaviour change, not a migration.
  EOT
}

variable "host_port" {
  type    = number
  default = 3001
}
