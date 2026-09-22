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

# `dsn_file` is gone. The DSN was a bind mount from
# /docker-volumes/memos/db_connection_string.txt on mindy -- a credential that
# existed only on that disk. It is generated in main.tf now from the values
# below. The old file can be deleted once this has applied.

variable "host_port" {
  type    = number
  default = 3007
}

# The org every project here lives in. Passed from ../../zitadel, which owns the
# org objects -- those are instance-level and not part of any one service.
variable "org_id" {
  type = string
}
