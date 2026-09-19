# renovate: datasource=docker depName=databasus/databasus
variable "image_tag" {
  type    = string
  default = "v3.51.0"
}

variable "host_port" {
  type        = number
  default     = 4005
  description = "Web UI. samson has no reverse proxy, so this is the only way in -- it is reached directly on the tailnet, not through traefik."
}

variable "data_path" {
  type        = string
  default     = "/docker-volumes/backup-server/databasus/data"
  description = <<-EOT
    databasus's own state: schedules, targets, credentials for the databases it
    backs up, and the dumps themselves (1.3 GB as of the 2026-08 backup audit).

    MUST ALREADY EXIST. The provider has no equivalent of compose's
    `create_host_path: true`, and a missing directory is not an error -- docker
    creates an empty one and databasus starts with no schedules configured,
    looking healthy while backing up nothing.
  EOT
}
