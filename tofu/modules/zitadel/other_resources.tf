resource "postgresql_role" "zitadel_user" {
  name     = "zitadel_user"
  login    = true
  password = var.user_password
}

resource "postgresql_role" "zitadel_root" {
  name     = "zitadel_root"
  login    = true
  password = var.root_password
}

resource "postgresql_database" "zitadel" {
  name  = "zitadel"
  owner = postgresql_role.zitadel_root.name
}

resource "docker_secret" "zitadel_masterkey" {
  name = "zitadel_masterkey_v1"
  data = base64encode(var.masterkey)
}

resource "docker_secret" "zitadel_config" {
  name = "zitadel_config_v1"
  data = base64encode(<<EOT
Log:
  Level: 'info'

ExternalDomain: auth.${var.domain}
ExternalPort: 443
ExternalSecure: true

TLS:
  Enabled: false

Database:
  postgres:
    Host: 'db'
    Port: 5432
    Database: zitadel
    User:
      Username: '${postgresql_role.zitadel_user.name}'
    Admin:
      Username: '${postgresql_role.zitadel_root.name}'
EOT
  )
}

resource "docker_secret" "zitadel_secrets" {
  name = "zitadel_secrets_v1"
  data = base64encode(<<EOT
Database:
  postgres:
    User:
      Password: '${postgresql_role.zitadel_user.password}'
    Admin:
      Password: '${postgresql_role.zitadel_root.password}'
EOT
  )
}

resource "docker_secret" "zitadel_init_steps" {
  name = "zitadel_init_steps_v1"
  data = base64encode(file("${path.module}/../../../home-eu-central-1/zitadel/zitadel-initial-steps.yaml"))
}
