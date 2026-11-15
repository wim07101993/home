resource "zitadel_project" "this" {
  name   = "test-server"
  org_id = var.zitadel_org_id

  project_role_check = true
  has_project_check  = true
}

resource "zitadel_project_role" "admin" {
  org_id       = var.zitadel_org_id
  project_id   = zitadel_project.this.id
  role_key     = "admin"
  display_name = "admin"
  group        = "admin"
}

resource "zitadel_application_oidc" "this" {
  org_id     = var.zitadel_org_id
  project_id = zitadel_project.this.id
  name       = "arcane"

  redirect_uris = [
    "http://${var.tailscale_ip}:${var.host_port}/auth/oidc/callback",
    "http://plop.home:${var.host_port}/auth/oidc/callback",
  ]
  response_types = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types    = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]

  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_BASIC"
  dev_mode         = true
}
