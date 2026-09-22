# memos' postgres database and role, on mindy.
#
# Moved here from ../../databases on 2026-09-22 as part of vertical slicing: the
# database sits with the only service that uses it, rather than in a shared
# module listing every database in the estate.
#
# The `postgresql` provider instance is passed by the root -- this module does
# not know or care which host it points at.

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "postgresql_role" "this" {
  name     = "memos"
  login    = true
  password = random_password.db.result

  # NOINHERIT, as this role was created. See ../../databases for the convention
  # -- the provider defaults to inherit = true, so it must be written out.
  inherit = false
}

resource "postgresql_database" "this" {
  name  = "memos"
  owner = postgresql_role.this.name

  lifecycle {
    prevent_destroy = true
  }
}
