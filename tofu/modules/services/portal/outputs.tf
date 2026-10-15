output "zitadel_app_dev" {
  description = "The dev client: the portal repo's scripts/dev-nextgen.sh takes it as ZITADEL_CLIENT_ID and ZITADEL_CLIENT_SECRET_FILE."
  sensitive   = true
  value = {
    kind          = "oidc"
    client_id     = zitadel_application_oidc.dev.client_id
    client_secret = zitadel_application_oidc.dev.client_secret
  }
}

output "zitadel_project_id" {
  value = zitadel_project.this.id
}
