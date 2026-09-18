# Read it with:
#
#   tofu output -raw filebrowser_admin_password
#
# The value is reset into filebrowser on every container start, so this is
# always the password that actually works -- there is no drift to reconcile.
output "admin_password" {
  value     = random_password.admin.result
  sensitive = true
}
