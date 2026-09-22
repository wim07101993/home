# renovate: datasource=docker depName=gtstef/filebrowser
variable "image_tag" {
  type    = string
  default = "1.5.6-stable-slim"
}

variable "traefik_network" {
  type = string
}

variable "db_network" {
  type = string
}

variable "config_path" {
  type        = string
  default     = "/docker-volumes/filebrowser/config"
  description = "Holds config.yaml and database.db. Read-write: filebrowser owns its database here."
}

variable "files_path" {
  type        = string
  default     = "/docker-volumes/filebrowser/files"
  description = <<-EOT
    The `audio` and `audio-archive` NFS mounts from samson land under here --
    see mindy/fstab. They are plain `_netdev` entries, NOT x-systemd.automount
    as this description used to claim. Must already exist: compose's
    `create_host_path: true` has no equivalent in this provider, and a missing
    directory is a silent failure rather than an error.
  EOT
}

variable "host_port" {
  type    = number
  default = 8900
}

# The document shares, local on mindy's `rafiki` volume since 2026-09-18.
#
# Each is mounted at /files/<name> INSIDE the container -- the same path it had
# over NFS, so filebrowser's own database of paths, shares and permissions needs
# no migration.
#
# They nest inside the /files bind, which still carries the remaining NFS
# submounts (audio, media, backups) from samson. Docker applies mounts in
# path-depth order, so these shadow the NFS ones.
variable "documents_path" {
  type = string
}

variable "document_shares" {
  type = list(string)
}

# THE SOURCE LIST, and the access a NEW user gets to each.
#
# `default_enabled` IS retroactive, unlike the permissions below. On every
# startup, cmd/user.go -> updateUserScopes grants each user a scope for any
# default_enabled source they are missing. Flip one to true and the next
# container start hands it to everyone who already has an account.
#
# Personal shares stay false. Setting one true would hand it to every user the
# OIDC provider auto-creates, which for /files/wim and /files/sara is precisely
# the wrong outcome.
variable "sources" {
  type = list(object({
    path            = string
    name            = string
    default_enabled = bool
  }))
}

variable "oidc_issuer_url" {
  type    = string
  default = "https://auth.wvl.app"
}

# NOT the client id from module.zitadel -- drive is still on the `home-old`
# project, like photos and memo. Switch this to
# module.zitadel.zitadel_application_oidc.drive.client_id as part of that
# migration, not before: changing it early logs everyone out of a working app.
variable "oidc_client_id" {
  type = string
}

# Members of this group in the `groups` claim are made admin. Unlike scopes,
# this IS re-applied on every login, for existing users too.
variable "oidc_admin_group" {
  type    = string
  default = "fb_admins"
}

# Permissions granted to a NEWLY CREATED user, and only then. updatePermissions
# returns early on `user.Version >= 1`, so this never reaches an existing
# account -- change those in the admin UI, or delete the user and let OIDC
# recreate it.
#
# `share` is off because share links are public URLs to family documents, and
# `api` because nothing here needs programmatic access.
variable "user_permissions" {
  type = object({
    api      = bool
    admin    = bool
    modify   = bool
    share    = bool
    realtime = bool
    delete   = bool
    create   = bool
    download = bool
  })
  default = {
    api      = false
    admin    = false
    modify   = true
    share    = false
    realtime = false
    delete   = true
    create   = true
    download = true
  }
}

# The audio share, local on rafiki since 2026-09-18. Mounted at /files/audio --
# the same container path it had over NFS, so config.yaml's source list and
# filebrowser's index are unaffected by the move.
#
# `audio-archive` stays on samson: it is archival, and it still arrives as an
# NFS submount through the /files bind.
variable "audio_path" {
  type = string
}

# The org this project lives in. Passed from ../../zitadel, which owns the org
# objects -- those are instance-level and not part of any one service.
variable "org_id" {
  type = string
}
