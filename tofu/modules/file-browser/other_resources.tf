resource "postgresql_role" "filebrowser" {
  name     = "filebrowser"
  login    = true
  password = var.db_password
}

resource "postgresql_database" "filebrowser" {
  name  = "filebrowser"
  owner = postgresql_role.filebrowser.name
}

resource "zitadel_application_oidc" "filebrowser" {
  project_id = var.zitadel_project_id
  org_id     = var.zitadel_org_id
  name       = "filebrowser"

  redirect_uris    = ["https://drive.${var.domain}/auth/callback"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_NONE"
}

resource "docker_secret" "filebrowser_config" {
  name = "filebrowser_config_v1"
  data = base64encode(templatefile("${path.module}/config.yaml.tftpl", {
    db_user    = postgresql_role.filebrowser.name
    db_password = postgresql_role.filebrowser.password
    db_name    = postgresql_database.filebrowser.name
    issuer_url = "https://auth.${var.domain}"
    client_id  = zitadel_application_oidc.filebrowser.client_id
  }))
}
