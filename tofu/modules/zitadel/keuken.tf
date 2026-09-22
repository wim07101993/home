# keuken.wvl.app -- kitchen-owl, on mindy. Was the `kitchen-owl` project.
#
# BEHAVIOUR CHANGE: the old project had has_project_check off, so anyone in the
# org could authenticate to it. It is on here, like every other project, which
# is the point of splitting them up. Kitchen-owl users need an explicit grant
# after the rebuild.

resource "zitadel_project" "keuken" {
  name   = "keuken"
  org_id = zitadel_org.home.id

  project_role_assertion = true
  project_role_check     = true
  has_project_check      = true
}

resource "zitadel_project_role" "keuken_family" {
  org_id       = zitadel_org.home.id
  project_id   = zitadel_project.keuken.id
  role_key     = "family"
  display_name = "family"
  group        = "family"
}

# There is no `transaction-importer` app here on purpose.
#
# It was rebuilt with the rest of the project on 2026-09-17 and deleted again by
# hand the same day. Carried over from the old kitchen-owl project, it used the
# device code flow, had no redirect URIs, and nothing in this repo referenced
# its client id -- so it was rebuilt out of completeness rather than need.
#
# Left out rather than re-added because tofu would mint a NEW client id for it,
# which is worse than absent: anything still holding the old one would fail in a
# way that looks like a permissions problem. Add it back deliberately, with
# whatever needs it, if that day comes.

resource "zitadel_application_oidc" "kitchen_owl_web_app" {
  org_id     = zitadel_org.home.id
  project_id = zitadel_project.keuken.id
  name       = "kitchen owl web-app"

  redirect_uris    = ["https://keuken.wvl.app/signin/redirect"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_BASIC"
}
