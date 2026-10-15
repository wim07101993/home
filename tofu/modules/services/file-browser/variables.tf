variable "traefik_network" {
  type = string
}

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

variable "zitadel_org_id" {
  type = string
}

variable "host_port" {
  type = number
}
