resource "postgresql_role" "memo" {
  name     = "memo"
  login    = true
  password = "memo_password_change_me" # TODO: use a generated secret
}

resource "postgresql_database" "memo" {
  name  = "memo"
  owner = postgresql_role.memo.name
}

resource "docker_secret" "memo_db_dsn" {
  name = "memo_db_dsn_v1"
  data = base64encode("postgres://${postgresql_role.memo.name}:${postgresql_role.memo.password}@db:5432/${postgresql_database.memo.name}?sslmode=disable")
}

