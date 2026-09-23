# Surfaced so the root can assemble the estate-wide zitadel outputs -- every
# client id in one place, even though the resources live with their service.
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
