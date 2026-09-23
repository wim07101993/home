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

# The org this project lives in. Passed from ../../zitadel, which owns the org
# objects -- those are instance-level and not part of any one service.
variable "org_id" {
  type = string
}

variable "superuser_password" {
  type      = string
  sensitive = true

  description = <<-EOT
    postgres superuser password on immich's own cluster.

    Generated in the ROOT (random_password.immich_pg_superuser), because it
    also configures the postgresql provider aliased at mindy:5434.

    It is written to a file in the container and re-applied on every start by
    assert-superuser-password.sh. That is what makes it a declared value rather
    than a fact about the day initdb ran -- POSTGRES_PASSWORD alone is read
    only when the data directory is empty, which on this cluster was years ago.

    Rotating it is an ordinary apply:

      tofu apply -replace=random_password.immich_pg_superuser
  EOT
}
