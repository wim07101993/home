# status.wvl.app -- gatus. A new project, not part of `home`.
#
# Separate because the audience is different: `home` is the family, this is
# whoever is on call for the estate. Splitting the projects is what makes that
# expressible as a grant rather than as a shared password.

resource "zitadel_project" "status" {
  name   = "status"
  org_id = zitadel_org.home.id

  project_role_assertion = true
  project_role_check     = true
  has_project_check      = true
}

resource "zitadel_project_role" "status_admin" {
  org_id       = zitadel_org.home.id
  project_id   = zitadel_project.status.id
  role_key     = "admin"
  display_name = "admin"
  group        = "admin"
}

resource "zitadel_application_oidc" "gatus" {
  org_id     = zitadel_org.home.id
  project_id = zitadel_project.status.id
  name       = "gatus"

  # Gatus requires this exact path; it is not configurable.
  redirect_uris    = ["https://status.wvl.app/authorization-code/callback"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_BASIC"
}
