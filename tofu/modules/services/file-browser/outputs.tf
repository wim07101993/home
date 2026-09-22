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

# Surfaced so the root can assemble the estate-wide zitadel outputs -- the
# cutover needs every client id in one place even though the resources now live
# with the service that uses them.
output "zitadel_app" {
  sensitive = true
  value = {
    kind          = "oidc"
    client_id     = zitadel_application_oidc.this.client_id
    client_secret = zitadel_application_oidc.this.client_secret
  }
}

output "zitadel_project_id" {
  value = zitadel_project.this.id
}
