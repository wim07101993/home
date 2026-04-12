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
  data = base64encode(<<EOT
FirstInstance:
  Org:
    Name: Home
    Human:
      UserName: wim
      FirstName: Wim
      LastName: Van Laer
      Email:
        Address: van.laer.wim@wvl.app
        Verified: true
      PreferredLanguage: en
      Password: Password1234!
      PasswordChangeRequired: true
EOT
  )
}

resource "zitadel_org" "default" {
  name = "Zitadel"
}

# Define the project for our home lab services
resource "zitadel_project" "homelab" {
  name              = "home"
  org_id            = zitadel_org.default.id
  has_project_check = false
}

output "zitadel_org_id" {
  value = zitadel_org.default.id
}

output "zitadel_project_id" {
  value = zitadel_project.homelab.id
}
