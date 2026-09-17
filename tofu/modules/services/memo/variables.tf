# renovate: datasource=docker depName=neosmemo/memos
variable "image_tag" {
  type    = string
  default = "0.26.2"
}

variable "traefik_network" {
  type        = string
  description = "traefik's network on mindy, passed from the reverse-proxy module."
}

variable "db_network" {
  type        = string
  default     = "db_db-network"
  description = <<-EOT
    mindy's postgres network. A plain string, not a reference: that stack is
    still compose-managed, so tofu does not own the network and must not try
    to. Becomes a module reference when mindy's postgres moves.
  EOT
}

variable "dsn_file" {
  type        = string
  default     = "/docker-volumes/memos/db_connection_string.txt"
  description = "Host path holding the postgres DSN. Note `memos`, not `memo` -- the directory does not match the repo's."
}

variable "host_port" {
  type    = number
  default = 3007
}
