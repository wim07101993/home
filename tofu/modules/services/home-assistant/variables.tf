# renovate: datasource=docker depName=homeassistant/home-assistant
variable "image_tag" {
  type    = string
  default = "2026.6.4"
}

# renovate: datasource=docker depName=ghcr.io/matter-js/matterjs-server
variable "matter_image_tag" {
  type    = string
  default = "1.1.5"
}

variable "config_path" {
  type        = string
  default     = "/docker-volumes/homeassistant/config"
  description = <<-EOT
    Home Assistant's own configuration directory.

    HOST STATE, not managed here. Home Assistant writes to this directory
    itself -- automations, the device registry, secrets and its sqlite
    recorder database all live in it -- so it cannot be generated from this
    repo. plop/homeassistant/configuration.yaml is a COPY for reference, not
    the source of truth, and the two can drift.
  EOT
}

variable "matter_data_path" {
  type        = string
  default     = "/docker-volumes/homeassistant/matterjs-server"
  description = <<-EOT
    The Matter fabric: certificates, the commissioned-device store, and the
    server's own identity.

    Losing it means re-commissioning every Matter device by hand. See
    README.md -- as of 2026-09-23 this directory was EMPTY and the real data
    was in an anonymous docker volume, because of a typo in the compose file.
  EOT
}

variable "serial_device" {
  type        = string
  default     = "/dev/ttyUSB0"
  description = <<-EOT
    The USB radio stick. Passed straight through.

    A FIXED PATH, which is not the same as a stable one: ttyUSB numbering is
    assigned in probe order, so adding a second USB serial device can renumber
    this and hand Home Assistant the wrong radio. /dev/serial/by-id/... is the
    stable spelling; changing to it is a separate, verifiable step and needs
    the actual id read off plop.
  EOT
}

variable "org_id" {
  type        = string
  description = "The zitadel org that owns the `home` project. From module.zitadel."
}

variable "tailscale_ip" {
  type        = string
  description = <<-EOT
    plop's tailnet address.

    Used in two places that must agree: the OIDC redirect URI, and the
    `trusted_ips` CIDR that exempts a network from `block_login`. Spelling it
    once is what stops those drifting.
  EOT
}
