# keuken's zitadel project, role and client.
#
# Moved here from ../../zitadel on 2026-09-22. The ORG is not here -- orgs are
# instance-level and stay in that module; this takes var.org_id.

resource "zitadel_project" "this" {
  name   = "keuken"
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
  name       = "kitchen owl web-app"

  redirect_uris    = ["https://keuken.wvl.app/signin/redirect"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_BASIC"
}
