# The kopia server UI password, for var.server_username. Sensitive: it grants
# access to browse and restore every snapshot this instance can see.
output "server_password" {
  value     = random_password.server_user.result
  sensitive = true
}
