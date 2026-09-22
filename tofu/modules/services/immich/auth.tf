# immich's zitadel project, role and OIDC client.
#
# Moved here from ../../zitadel on 2026-09-22. The ORG stays there.
#
# NOT wired into the container: immich is still on the `home-old` client id,
# configured inside immich itself. Pointing it at this app is a separate,
# deliberate cutover -- see ../../../main.tf.

resource "zitadel_project" "this" {
  name   = "photos"
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
  name       = "immich"

  redirect_uris = [
    "https://photos.wvl.app/auth/login",
    "https://photos.wvl.app/user-settings",
    "https://photos.wvl.app/api/oauth/mobile-redirect",
  ]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type         = "OIDC_APP_TYPE_USER_AGENT"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_NONE"

  access_token_type           = "OIDC_TOKEN_TYPE_JWT"
  access_token_role_assertion = true
  id_token_role_assertion     = true
}
