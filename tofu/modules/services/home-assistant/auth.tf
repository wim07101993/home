# Home Assistant's zitadel client -- the vertical slice.
#
# This lived in ../../zitadel until 2026-09-23, with a comment saying it stayed
# there only because plop had no service module. It has one now.
#
# has_project_check = true, like every other project: without a user grant on
# this project a person cannot get a token for the app AT ALL. That is the
# point of the split, and it is also the thing that will lock everyone out of
# Home Assistant if the grants are not in place before the cutover. See
# README.md.
resource "zitadel_project" "this" {
  name   = "home"
  org_id = var.org_id

  project_role_assertion = true
  project_role_check     = true
  has_project_check      = true
}

resource "zitadel_project_role" "family" {
  org_id       = var.org_id
  project_id   = zitadel_project.this.id
  role_key     = "family"
  display_name = "family"
  group        = "family"
}

resource "zitadel_application_oidc" "this" {
  org_id     = var.org_id
  project_id = zitadel_project.this.id
  name       = "home assistant"

  # Three, because Home Assistant is reached by three names depending on where
  # you are: the LAN hostname over https and http, and the tailnet address.
  # zitadel matches the redirect exactly, so a missing one is a login that
  # fails only from one network.
  redirect_uris = [
    "https://plop.home:8123/auth/openid/callback",
    "http://${var.tailscale_ip}:8123/auth/openid/callback",
    "http://plop.home:8123/auth/openid/callback",
  ]
  response_types = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types    = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]

  app_type          = "OIDC_APP_TYPE_WEB"
  auth_method_type  = "OIDC_AUTH_METHOD_TYPE_BASIC"
  access_token_type = "OIDC_TOKEN_TYPE_JWT"
}
