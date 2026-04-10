resource "docker_secret" "db_password" {
  name = "db_password_v1"
  data = base64encode(var.db_password)
}

