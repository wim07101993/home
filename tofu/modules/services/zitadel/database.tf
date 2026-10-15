resource "random_password" "db_user" {
  length  = 32
  special = false
}

resource "postgresql_role" "user" {
  name     = "zitadel_user"
  login    = true
  inherit  = false
  password = random_password.db_user.result
}

resource "random_password" "db_root" {
  length  = 32
  special = false
}

resource "postgresql_role" "root" {
  name      = "zitadel_root"
  login     = true
  inherit   = false
  superuser = true
  password  = random_password.db_root.result
}

resource "postgresql_database" "this" {
  name  = "zitadel"
  owner = postgresql_role.root.name

  lifecycle {
    prevent_destroy = true
  }
}
