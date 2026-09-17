# renovate: datasource=docker depName=louislam/uptime-kuma
variable "image_tag" {
  type    = string
  default = "1.23.13"
}

variable "traefik_network" {
  type = string
}

variable "data_path" {
  type        = string
  default     = "/docker-volumes/uptime-kuma/data"
  description = <<-EOT
    Holds the SQLite database: monitors, history, and the admin account.

    MUST EXIST BEFORE THE FIRST APPLY. There is no `create_host_path` in this
    provider, and docker will happily create it as root-owned, which uptime-kuma
    cannot write to:

      ssh root@<bumba> mkdir -p /docker-volumes/uptime-kuma/data
  EOT
}

variable "host_port" {
  type        = number
  default     = 3008
  description = "Free on bumba: 3005 and 3006 were released when score moved to mindy."
}
