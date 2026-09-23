# renovate: datasource=docker depName=alpine/socat
variable "image_tag" {
  type    = string
  default = "1.8.0.3"
}

variable "target_host" {
  type        = string
  description = "The Storage Box FQDN. Resolved inside the container, on bumba -- which is what makes the connection originate in Hetzner."
}

variable "target_port" {
  type    = number
  default = 23

  description = <<-EOT
    23, not 22. Hetzner Storage Boxes serve SSH/SFTP on 23; port 22 is a
    restricted shell with no SFTP subsystem.
  EOT
}

variable "listen_port" {
  type    = number
  default = 2223

  description = <<-EOT
    Where clients connect on bumba's TAILNET address.

    Not 22, and not 23: bumba's own sshd owns 22, and this must not look like
    it. The port is part of the known_hosts pattern on every client, so
    changing it later means regenerating those -- see ../kopia.
  EOT
}

variable "tailscale_ip" {
  type        = string
  description = "bumba's tailnet address. The listener binds HERE and nowhere else -- bound to 0.0.0.0 this would be an open relay into a Storage Box that only trusts where the packet came from."
}
