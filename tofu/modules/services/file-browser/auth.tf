# drive's zitadel project, role and OIDC client.
#
# Moved here from ../../zitadel on 2026-09-22. The ORG stays there.
#
# NOT wired into config.yaml: filebrowser is still on the `home-old` client id
# (var.oidc_client_id). Switching it to zitadel_application_oidc.this.client_id
# is the cutover that variable's comment describes -- logging everyone out, so
# it happens on purpose and not as a side effect of this move.

resource "zitadel_project" "this" {
  name   = "drive"
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
  name       = "drive"

  redirect_uris = ["https://drive.wvl.app/api/auth/oidc/callback"]

  # TYPO IN THE LIVE CONFIG, reproduced deliberately: `.wvl.app.com`. Fixing it
  # here would bundle a silent behaviour change into a migration. Correct it
  # afterwards, on purpose, once the rebuild is known good.
  post_logout_redirect_uris = ["https://drive.wvl.app.com/login"]

  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type         = "OIDC_APP_TYPE_USER_AGENT"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_NONE"

  access_token_type           = "OIDC_TOKEN_TYPE_JWT"
  id_token_role_assertion     = true
  id_token_userinfo_assertion = true
}
