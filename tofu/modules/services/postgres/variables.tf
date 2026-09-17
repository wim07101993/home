variable "image_tag" {
  type        = string
  default     = "17.10-alpine3.23"
  description = "Pinned at what bumba runs today, so the cutover changes one thing."
}

variable "container_name" {
  type    = string
  default = "database-db-1"
}

variable "network_name" {
  type        = string
  default     = "database_db-network"
  description = "The compose-created name, kept exactly. zitadel and score stay on compose and reference it as `external: true`."
}

variable "network_alias" {
  type        = string
  default     = "db"
  description = <<-EOT
    THE most important value in this module.

    zitadel-config.yaml has `Database.postgres.Host: 'db'`, and score's DSN
    resolves `db` the same way. That name is not the container name -- it is
    the network ALIAS compose adds for the service. Recreate the container
    without it and zitadel cannot reach its database, which takes down auth for
    every service in the estate.
  EOT
}

variable "network_labels" {
  type        = map(string)
  default     = {}
  description = "Labels already on the existing network, from `docker network inspect`. Reproduced exactly so the import plans clean."
}

variable "data_path" {
  type        = string
  default     = "/docker-volumes/db/data"
  description = <<-EOT
    A SYMLINK to /mnt/HC_Volume_103225027/db/data/ -- the Hetzner volume.
    Getting this wrong does not error: postgres initialises a fresh, empty
    cluster beside the real one and everything appears to start fine.
  EOT
}

variable "password_file" {
  type        = string
  default     = "/docker-volumes/db/db_password.txt"
  description = "Compose mounted this as a `secret`; here it is a read-only bind to the same path."
}
