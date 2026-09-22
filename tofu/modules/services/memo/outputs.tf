# Surfaced so the root can assemble the estate-wide `zitadel_apps` and
# `zitadel_project_ids` outputs -- the cutover needs client ids in one place
# even though the resources now live per service.
output "zitadel_app" {
  description = "memo's OIDC client id and secret."
  sensitive   = true
  value = {
    kind          = "oidc"
    client_id     = zitadel_application_oidc.this.client_id
    client_secret = zitadel_application_oidc.this.client_secret
  }
}

output "zitadel_project_id" {
  value = zitadel_project.this.id
}
