# renovate: datasource=docker depName=ghcr.io/immich-app/immich-server
variable "image_tag" {
  type        = string
  default     = "v3.1.0"
  description = "Server and machine-learning share a tag; they are released together."
}

variable "redis_image" {
  type    = string
  default = "docker.io/valkey/valkey:9@sha256:3b55fbaa0cd93cf0d9d961f405e4dfcc70efe325e2d84da207a0a8e6d8fde4f9"
}

variable "postgres_image" {
  type        = string
  default     = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23"
  description = "immich's own postgres, with vectorchord and pgvecto.rs. Not interchangeable with the plain postgres the rest of the estate runs, and a major upgrade needs immich's documented procedure."
}

variable "traefik_network" {
  type = string
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = <<-EOT
    The EXISTING password. Not generated: the cluster at
    /docker-volumes/immich/postgres was initialised with it, and changing
    POSTGRES_PASSWORD on an initialised cluster does nothing except break the
    app's ability to connect.

    Read it off the running container:
      ssh root@<mindy> docker inspect immich_postgres \\
        | jq -r '.[0].Config.Env[]|select(startswith("POSTGRES_PASSWORD"))'
  EOT
}

variable "library_path" {
  type        = string
  default     = "/docker-volumes/immich/immich-data"
  description = <<-EOT
    THE NFS MOUNT FROM SAMSON: 100.71.248.106:/export/photos, per mindy's
    /etc/fstab. Boot-time, not an automount.

    The compose stack said `/docker-volumes/immich/library-samson`, which does
    not exist on mindy at all. The running container predates that edit, which
    is the only reason immich still works: with `create_host_path: true`, the
    next portainer redeploy would have created that directory empty and started
    immich against a library with no photos in it and no error anywhere.
  EOT
}

variable "db_data_path" {
  type    = string
  default = "/docker-volumes/immich/postgres"
}
