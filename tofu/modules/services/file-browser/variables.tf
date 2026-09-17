# renovate: datasource=docker depName=gtstef/filebrowser
variable "image_tag" {
  type    = string
  default = "1.5.6-stable-slim"
}

variable "traefik_network" {
  type = string
}

variable "db_network" {
  type = string
}

variable "config_path" {
  type        = string
  default     = "/docker-volumes/filebrowser/config"
  description = "Holds config.yaml and database.db. Read-write: filebrowser owns its database here."
}

variable "files_path" {
  type        = string
  default     = "/docker-volumes/filebrowser/files"
  description = <<-EOT
    Nine x-systemd.automount NFS mounts from samson land under here -- see
    mindy/fstab. Must already exist: compose's `create_host_path: true` has no
    equivalent in this provider, and a missing directory is a silent failure
    rather than an error.
  EOT
}

variable "host_port" {
  type    = number
  default = 8900
}
