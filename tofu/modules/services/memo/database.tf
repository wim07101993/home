resource "random_password" "db" {
  length  = 32
  special = false
}

resource "postgresql_role" "this" {
  name     = "memos"
  login    = true
  password = random_password.db.result
  inherit  = false
}

resource "postgresql_database" "this" {
  name  = "memos"
  owner = postgresql_role.this.name

  lifecycle {
    prevent_destroy = true
  }
}
