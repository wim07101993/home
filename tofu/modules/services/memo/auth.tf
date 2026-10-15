resource "zitadel_project" "this" {
  name   = "memo"
  org_id = var.zitadel_org_id

  project_role_assertion = true
  project_role_check     = true
  has_project_check      = true
}

resource "zitadel_project_role" "family" {
  org_id       = var.zitadel_org_id
  project_id   = zitadel_project.this.id
  role_key     = "family"
  display_name = "family"
  group        = "family"
}

resource "zitadel_application_oidc" "this" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.this.id
  name       = "memo"

  redirect_uris             = ["https://memo.wvl.app/auth/callback"]
  post_logout_redirect_uris = ["https://memo.wvl.app"]
  response_types            = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types               = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]

  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_BASIC"
}
