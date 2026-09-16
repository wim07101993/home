# bumba's postgres. Adopted 2026-09-16 from ./discover.sh output.
#
# `owner` is a plain string: adopting a database does not require its role to
# be a resource, which is what lets this first pass skip roles entirely.
# See imports.tf for why roles are not here yet.

resource "postgresql_database" "zitadel" {
  name  = "zitadel"
  owner = "zitadel_root"

  lifecycle {
    # A dropped database is not a slow apply. memos on 2026-09-15 is the
    # worked example -- deliberate that time, and the reason this layer's own
    # state lives in a database of its own.
    prevent_destroy = true
  }
}

resource "postgresql_database" "score" {
  name  = "score"
  owner = "postgres"

  lifecycle {
    prevent_destroy = true
  }
}
