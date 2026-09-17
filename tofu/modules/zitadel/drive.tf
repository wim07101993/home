# drive.wvl.app -- file-browser, on mindy.

resource "zitadel_project" "drive" {
  name   = "drive"
  org_id = local.org_home

  project_role_assertion = true
  project_role_check     = true
  has_project_check      = true
}

resource "zitadel_project_role" "drive_family" {
  org_id       = local.org_home
  project_id   = zitadel_project.drive.id
  role_key     = "family"
  display_name = "family"
  group        = "family"
}

resource "zitadel_application_oidc" "drive" {
  org_id     = local.org_home
  project_id = zitadel_project.drive.id
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
