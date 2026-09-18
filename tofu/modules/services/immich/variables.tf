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
  default     = "/mnt/rafiki/photos"
  description = <<-EOT
    LOCAL, on the `rafiki` volume attached to mindy. Moved off NFS 2026-09-18.

    It was 100.71.248.106:/export/photos -- a hard NFS v3 mount from samson,
    over a residential WAN, per mindy's /etc/fstab. That is the failure class
    the 2026-08 array incident ran entirely through: filebrowser blocking in
    stat(), kopia's nightly tree-walk stalling, `nfs: server not responding`.
    Measured 2026-09-18: `du` over that mount took ~2 HOURS to walk 67 GB in
    45,549 files, and could not finish `thumbs` in 30 minutes.

    The CONTAINER path is unchanged at /data, which is the whole reason this is
    a one-line move: immich stores asset paths relative to /data in its
    database, so nothing in postgres needs migrating.

    Restored from the kopia repository on the Storage Box rather than copied
    from samson -- Hetzner-internal, and it avoids pushing 67 GB up an ADSL
    uplink whose upstream is the weak direction.

    Historical note, because it nearly bit: the compose stack said
    `/docker-volumes/immich/library-samson`, which does not exist on mindy at
    all. The running container predated that edit, which is the only reason
    immich still worked -- with `create_host_path: true`, the next portainer
    redeploy would have created that directory empty and started immich against
    a library with no photos and no error anywhere.
  EOT
}

variable "db_data_path" {
  type    = string
  default = "/docker-volumes/immich/postgres"
}
