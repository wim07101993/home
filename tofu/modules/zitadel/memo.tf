# memo.wvl.app -- memos, on mindy.
#
# Not in the split you described, but it was in the old `home` project and
# needed somewhere to live. Its own project, like the rest.
#
# This is the app that proved the whole premise: memos stores the OIDC `sub`
# as the account's username, so the 45 notes survive only because users are
# never recreated. See orgs.tf.

resource "zitadel_project" "memo" {
  name   = "memo"
  org_id = local.org_home

  project_role_assertion = true
  project_role_check     = true
  has_project_check      = true
}

resource "zitadel_project_role" "memo_family" {
  org_id       = local.org_home
  project_id   = zitadel_project.memo.id
  role_key     = "family"
  display_name = "family"
  group        = "family"
}

resource "zitadel_application_oidc" "memo" {
  org_id     = local.org_home
  project_id = zitadel_project.memo.id
  name       = "memo"

  redirect_uris             = ["https://memo.wvl.app/auth/callback"]
  post_logout_redirect_uris = ["https://memo.wvl.app"]
  response_types            = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types               = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]

  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_BASIC"
}
