# score's postgres database and role.
#
# Moved here from ../../databases on 2026-09-22 as part of vertical slicing.

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "postgresql_role" "this" {
  name     = "score_api"
  login    = true
  password = random_password.db.result

  # NOINHERIT -- see ../../databases for the convention.
  inherit = false
}

resource "postgresql_database" "this" {
  name  = "score"
  owner = postgresql_role.this.name

  lifecycle {
    prevent_destroy = true
  }
}
