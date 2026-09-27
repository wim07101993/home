# renovate: datasource=docker depName=postgres
variable "image_tag" {
  type        = string
  default     = "17.10-alpine3.23"
  description = "Both hosts run the same version. A major upgrade is a dump and restore, not a tag bump."
}

variable "container_name" {
  type        = string
  description = "No default, deliberately: bumba's is `database-db-1` and mindy's is `db`, and a module silently inheriting the wrong one would point at the wrong daemon's container."
}

variable "network_name" {
  type        = string
  description = "The compose-created name, kept exactly. Other stacks attach to it as `external: true`."
}

variable "network_labels" {
  type        = map(string)
  description = "Labels already on the existing network, from `docker network inspect`. Reproduced exactly so the import plans clean -- a missing label forces replacement of a network every dependent stack is attached to."
}

variable "network_alias" {
  type        = string
  default     = "db"
  description = <<-EOT
    THE most important value in this module, and it is the same on both hosts.

    On bumba, zitadel-config.yaml sets `Database.postgres.Host: 'db'`. On mindy,
    memos and filebrowser resolve the same name. That is not the container name
    -- it is the network ALIAS compose adds for the service, and compose gave it
    for free. `docker_container` does not. Recreate without it and every
    dependent service loses its database.
  EOT
}

variable "data_path" {
  type        = string
  default     = "/docker-volumes/db/data"
  description = <<-EOT
    PGDATA, as a bind mount. A REAL DIRECTORY on both hosts.

    It was a symlink on bumba, to /mnt/HC_Volume_103225027/db/data/ on the
    Hetzner volume, until 2026-09-18. That volume is now attached to mindy as
    /mnt/rafiki and bumba's cluster lives on its root disk (/dev/sda1) --
    verified 2026-09-27. Do not go looking for the symlink.

    Getting this wrong does not error: postgres runs initdb, builds an empty
    cluster beside the real one, and reports itself healthy.
  EOT
}

variable "password_file" {
  type        = string
  default     = "/docker-volumes/db/db_password.txt"
  description = "Compose mounted this as a `secret`; without swarm that is a read-only bind either way."
}
