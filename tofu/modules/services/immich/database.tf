resource "postgresql_role" "this" {
  name      = "immich"
  login     = true
  superuser = true
  password  = random_password.db.result

  skip_reassign_owned = true
  depends_on          = [docker_container.postgres]
}

resource "postgresql_grant_role" "databasus_read_all" {
  role       = "databasus-a246973a"
  grant_role = "pg_read_all_data"
}
