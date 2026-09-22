# plop's Home Assistant. Not public -- reached on the home network or the
# tailnet, hence a .home name and a tailnet IP among the redirect URIs.

resource "zitadel_project" "home" {
  name   = "home"
  org_id = zitadel_org.home.id

  project_role_assertion = true
  project_role_check     = true
  has_project_check      = true
}

resource "zitadel_project_role" "home_family" {
  org_id       = zitadel_org.home.id
  project_id   = zitadel_project.home.id
  role_key     = "family"
  display_name = "family"
  group        = "family"
}

resource "zitadel_application_oidc" "home_assistant" {
  org_id     = zitadel_org.home.id
  project_id = zitadel_project.home.id
  name       = "home assistant"

  redirect_uris = [
    "https://plop.home:8123/auth/openid/callback",
    "http://100.117.36.52:8123/auth/openid/callback",
    "http://plop.home:8123/auth/openid/callback",
  ]
  response_types = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types    = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]

  # No appType or authMethodType on the live app: the WEB / BASIC defaults.
  app_type          = "OIDC_APP_TYPE_WEB"
  auth_method_type  = "OIDC_AUTH_METHOD_TYPE_BASIC"
  access_token_type = "OIDC_TOKEN_TYPE_JWT"
}
