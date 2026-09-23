# renovate: datasource=docker depName=databasus/databasus
variable "image_tag" {
  type    = string
  default = "v3.51.0"
}

variable "host_port" {
  type        = number
  default     = 4005
  description = "Web UI. samson has no reverse proxy, so this is the only way in -- it is reached directly on the tailnet, not through traefik."
}

variable "dumps_path" {
  type    = string
  default = "/export/backups/backup-server/databasus/data/backups"

  description = <<-EOT
    Where the dump FILES go -- on samson's array, inside the tree exported to
    mindy as /export/backups, which is what kopia snapshots.

    Mounted over var.data_path/backups rather than moving the whole data
    directory, because that directory also holds databasus's own embedded
    postgres (`pgdata`). The array is btrfs; a postgres cluster on
    copy-on-write storage is a performance problem nobody asked for. Nested
    binds apply in path-depth order, so the state stays on ext4 and only the
    dumps land on the array.

    databasus has no setting for this -- its `local_storages` table has no path
    column and the location is hardcoded to <data-dir>/backups inside the
    container. The mount is the only lever.

    UNTIL 2026-09-23 the dumps were written to the root disk and kopia was
    snapshotting a COPY of this directory that had stopped updating on
    2026-08-01. Same path shape on a different filesystem, seven weeks stale,
    and nothing said a word. See README.md.
  EOT
}

variable "data_path" {
  type        = string
  default     = "/docker-volumes/backup-server/databasus/data"
  description = <<-EOT
    databasus's own state: schedules, targets, credentials for the databases it
    backs up, and the dumps themselves (1.3 GB as of the 2026-08 backup audit).

    MUST ALREADY EXIST. The provider has no equivalent of compose's
    `create_host_path: true`, and a missing directory is not an error -- docker
    creates an empty one and databasus starts with no schedules configured,
    looking healthy while backing up nothing.
  EOT
}

# renovate: datasource=docker depName=curlimages/curl
variable "checker_image_tag" {
  type    = string
  default = "8.11.1"
}

variable "gatus_token" {
  type        = string
  sensitive   = true
  description = "Bearer token for gatus's external endpoints. From modules/services/gatus, not typed in."
}

variable "gatus_base_url" {
  type        = string
  description = "e.g. https://status.wvl.app/api/v1/endpoints -- the checker appends the endpoint name."
}

variable "max_age_seconds" {
  type        = number
  default     = 93600
  description = <<-EOT
    How old the newest dump may be before the database reports down. 26h:
    the daily schedule plus room for a slow run.

    Must stay under the heartbeat interval on the gatus side, or a database
    that stopped being dumped would be reported as healthy right up until the
    heartbeat expired -- which is the failure this is meant to catch early.
  EOT
}

variable "check_interval_seconds" {
  type        = number
  default     = 3600
  description = "Seconds between sweeps. Hourly, so three consecutive bad sweeps (gatus's failure-threshold) means mail within about three hours."
}

variable "monitored" {
  type = map(object({
    prefix    = string
    min_bytes = number
  }))
  description = <<-EOT
    The databases to check, keyed by the gatus endpoint suffix -- the endpoint
    is `backups_databasus-<key>` and must exist in ../gatus/config.yaml.

    `prefix` is how databasus names the file, which is the DISPLAY name and so
    carries its capitalisation: `KitchenOwl-20260922-...`, but `zitadel-...`.

    `min_bytes` is a floor, not an expectation: roughly half of what the
    database produces today. Generous enough that ordinary shrinkage does not
    page anyone, tight enough to catch the 64-byte dumps that databasus wrote
    while reporting nothing. It does not catch a dump that is truncated at 60%
    -- nothing short of a restore test does, and that is a bigger piece of work
    than this one.
  EOT
}
