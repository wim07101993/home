# score's zitadel project, roles and two clients -- the API the backend
# introspects tokens with, and the web app the frontend logs in through.
#
# Moved here from ../../zitadel on 2026-09-22. The ORG stays there.
#
# BOTH APPS MUST BE IN THIS PROJECT. The frontend obtains the token; the API
# introspects it and looks for urn:zitadel:iam:org:project:roles. Split them
# across projects and every request is authenticated and then refused.

resource "zitadel_project" "this" {
  name   = "Score"
  org_id = var.org_id

  project_role_assertion = true
  project_role_check     = true
  has_project_check      = true
}

resource "zitadel_project_role" "editor" {
  org_id       = var.org_id
  project_id   = zitadel_project.this.id
  role_key     = "score_editor"
  display_name = "Score editor"
}

resource "zitadel_project_role" "viewer" {
  org_id       = var.org_id
  project_id   = zitadel_project.this.id
  role_key     = "score_viewer"
  display_name = "score viewer"
}

resource "zitadel_application_api" "api" {
  org_id     = var.org_id
  project_id = zitadel_project.this.id
  name       = "score-api"

  # No authMethodType on the live app, which is the BASIC default.
  auth_method_type = "API_AUTH_METHOD_TYPE_BASIC"
}

resource "zitadel_application_oidc" "web" {
  org_id     = var.org_id
  project_id = zitadel_project.this.id
  name       = "score-web-app"

  redirect_uris             = ["https://score.wvl.app/"]
  post_logout_redirect_uris = ["https://score.wvl.app/"]
  response_types            = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types               = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type                  = "OIDC_APP_TYPE_USER_AGENT"
  auth_method_type          = "OIDC_AUTH_METHOD_TYPE_NONE"

  id_token_role_assertion = true

  # The only app on loginV2 (the zitadel-login container); everything else is
  # still loginV1. If the provider cannot express that, set it in the console
  # after creation and note it here.
}
