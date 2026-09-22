# kitchen-owl's postgres database and role.
#
# Moved here from ../../databases on 2026-09-22 as part of vertical slicing: the
# database sits with the only service that uses it. The `postgresql` provider
# instance is passed by the root -- this module does not know which host it is.

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "postgresql_role" "this" {
  name     = "kitchenowl"
  login    = true
  password = random_password.db.result

  # NOINHERIT -- see ../../databases for the convention. The provider defaults
  # to inherit = true, so it must be written out on every role.
  inherit = false
}

resource "postgresql_database" "this" {
  name  = "kitchenowl"
  owner = postgresql_role.this.name

  lifecycle {
    prevent_destroy = true
  }
}
