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
