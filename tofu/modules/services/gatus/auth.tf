# gatus' zitadel project, role and OIDC client.
#
# Moved here from ../../zitadel on 2026-09-22. The ORG stays there.

resource "zitadel_project" "this" {
  name   = "status"
  org_id = var.org_id

  project_role_assertion = true
  project_role_check     = true
  has_project_check      = true
}

resource "zitadel_project_role" "admin" {
  org_id       = var.org_id
  project_id   = zitadel_project.this.id
  role_key     = "admin"
  display_name = "admin"
  group        = "admin"
}

resource "zitadel_application_oidc" "this" {
  org_id     = var.org_id
  project_id = zitadel_project.this.id
  name       = "gatus"

  # Gatus requires this exact path; it is not configurable.
  redirect_uris    = ["https://status.wvl.app/authorization-code/callback"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_BASIC"
}
