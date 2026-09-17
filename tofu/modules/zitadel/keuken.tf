# keuken.wvl.app -- kitchen-owl, on mindy. Was the `kitchen-owl` project.
#
# BEHAVIOUR CHANGE: the old project had has_project_check off, so anyone in the
# org could authenticate to it. It is on here, like every other project, which
# is the point of splitting them up. Kitchen-owl users need an explicit grant
# after the rebuild.

resource "zitadel_project" "keuken" {
  name   = "keuken"
  org_id = local.org_home

  project_role_assertion = true
  project_role_check     = true
  has_project_check      = true
}

resource "zitadel_project_role" "keuken_family" {
  org_id       = local.org_home
  project_id   = zitadel_project.keuken.id
  role_key     = "family"
  display_name = "family"
  group        = "family"
}

resource "zitadel_application_oidc" "transaction_importer" {
  org_id     = local.org_home
  project_id = zitadel_project.keuken.id
  name       = "transaction-importer"

  # Device code flow: no redirect URIs, by design.
  redirect_uris    = []
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_DEVICE_CODE"]
  app_type         = "OIDC_APP_TYPE_NATIVE"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_NONE"
}

resource "zitadel_application_oidc" "kitchen_owl_web_app" {
  org_id     = local.org_home
  project_id = zitadel_project.keuken.id
  name       = "kitchen owl web-app"

  redirect_uris    = ["https://keuken.wvl.app/signin/redirect"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_BASIC"
}
