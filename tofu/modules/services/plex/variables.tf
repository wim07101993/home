# renovate: datasource=docker depName=plexinc/pms-docker
variable "image_tag" {
  type    = string
  default = "1.43.2.10687-563d026ea"

  description = <<-EOT
    PINNED, where the live container ran `:latest`. A floating tag means the
    version running is whatever the last `docker pull` happened to fetch, which
    is not something this repo can describe.

    THE BUILD SUFFIX IS PART OF THE TAG. samson/plex/docker-compose.yaml said
    `1.43.3.10896`, which has never existed -- the real tag is
    `1.43.3.10896-cb3ebc72d`. So that compose file could not have deployed, and
    the stack quietly ran `:latest` instead. Nothing surfaced the mismatch
    until this migration tried to pull it.

    This is the version that WAS running (`:latest` resolved here), chosen over
    the newer one because the cutover happened with plex already stopped.
    Upgrading is a separate one-line change, made deliberately and with the
    service up.
  EOT
}

variable "config_path" {
  type        = string
  default     = "/docker-volumes/plex"
  description = <<-EOT
    Plex's library database, metadata and thumbnails -- 14 GB, and the only
    part of this service that is not reproducible. Losing it means re-scanning
    every file and losing watch state, playlists and collections.

    NOT backed up. See README.md.
  EOT
}

variable "media_path" {
  type    = string
  default = "/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300/media"

  description = <<-EOT
    The media library on samson's array, addressed by OMV's by-uuid path
    rather than /export/media.

    Both are the same filesystem -- `/export/media` is `/dev/sde[/media]`, the
    NFS export of this directory -- but the by-uuid path is what the array
    actually mounts, and reaching it through the export would put plex's reads
    through NFS on the machine that serves it.
  EOT
}
