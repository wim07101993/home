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
  data = base64encode(<<EOT
server:
  port: 80
  database: "postgres://${postgresql_role.filebrowser.name}:${postgresql_role.filebrowser.password}@db:5432/${postgresql_database.filebrowser.name}?sslmode=disable"
  sources:
    - path: "/files/wim"
      name: "Wim privé"
      config:
        defaultEnabled: false
    - path: "/files/sara"
      name: "Sara privé"
      config:
        defaultEnabled: false
    - path: "/files/gezin-officieel"
      name: "Gezin officieel"
      config:
        defaultEnabled: false
    - path: "/files/gezin-officieel-archive"
      name: "Gezin officieel archive"
      config:
        defaultEnabled: false
    - path: "/files/audio"
      name: "Audio"
      config:
        defaultEnabled: false
    - path: "/files/audio-archive"
      name: "Audio archive"
      config:
        defaultEnabled: false

auth:
  methods:
    password:
      enabled: true
    oidc:
      enabled: true
      issuerUrl: "https://auth.${var.domain}"
      clientId: "${zitadel_application_oidc.filebrowser.client_id}"
      scopes: "openid profile email groups"
      userIdentifier: "preferred_username"
      createUser: true
EOT
  )
}
