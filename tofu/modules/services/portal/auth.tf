# The home portal (github.com/wim07101993/home_portal) signs people in through
# zitadel-nextgen, which offers "Sign in with Zitadel" with this project's
# client. nextgen reads no roles: everyone it signs in sees every app. So who
# may use the portal is decided HERE, by project_role_check -- only users with
# the family role on this project get past zitadel's login. Grants are given
# by hand in the console, like every other project's (see modules/zitadel).

resource "zitadel_project" "this" {
  name   = "portal"
  org_id = var.zitadel_org_id

  project_role_check = true
  has_project_check  = true
}

resource "zitadel_project_role" "family" {
  org_id       = var.zitadel_org_id
  project_id   = zitadel_project.this.id
  role_key     = "family"
  display_name = "family"
  group        = "family"
}

# For running the portal and its nextgen on a laptop (scripts/dev-nextgen.sh
# in the portal repo). dev_mode is what lets zitadel accept http redirect
# URIs; the deployed portal gets its own app, without it, when this module
# takes over from homepage.
#
# nextgen alpha.25 calls back on one route for every provider; later versions
# on one per provider, hence both.
resource "zitadel_application_oidc" "dev" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.this.id
  name       = "home portal (dev)"

  redirect_uris = [
    "http://localhost:3000/__nextgen/idp/callback",
    "http://localhost:3000/__nextgen/idp/zitadel/callback",
  ]
  response_types = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types    = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]

  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_BASIC"
  dev_mode         = true
}
