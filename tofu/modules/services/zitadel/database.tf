# zitadel's postgres database and its two roles, on BUMBA.
#
# Moved here from ../../databases on 2026-09-22 as part of vertical slicing.
# The `postgresql` provider instance is passed by the root and points at bumba;
# this module does not know that, which is the point.
#
# TWO ROLES, not one. zitadel connects as `zitadel_user` for normal operation
# and as `zitadel_root` for the migrations it runs at boot -- which need to
# create and alter objects it does not own.

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
