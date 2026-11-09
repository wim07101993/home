variable "oidc_issuer_url" {
  type    = string
  default = "https://auth.wvl.app"
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
    share    = bool
    realtime = bool
  })
  default = {
    api      = false
    admin    = false
    share    = false
    realtime = false
  }
}

# What a user may do in a share, set on every source. Applied only to a user's
# source that has no permissions yet: a new user, or a source newly enabled for
# an existing one. Existing accounts keep theirs -- change those in the admin UI.
variable "file_permissions" {
  type = object({
    view     = bool
    download = bool
    modify   = bool
    delete   = bool
    create   = bool
  })
  default = {
    view     = true
    download = true
    modify   = true
    delete   = true
    create   = true
  }
}

variable "zitadel_org_id" {
  type = string
}

variable "host_port" {
  type = number
}
