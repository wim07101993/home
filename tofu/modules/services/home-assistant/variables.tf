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

variable "zitadel_org_id" {
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
