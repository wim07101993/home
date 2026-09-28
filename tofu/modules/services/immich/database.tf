resource "postgresql_role" "this" {
  name      = "immich"
  login     = true
  superuser = true
  password  = random_password.db.result

  skip_reassign_owned = true
  depends_on          = [docker_container.postgres]
}
