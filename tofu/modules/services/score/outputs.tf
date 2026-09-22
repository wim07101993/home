# Surfaced so the root can assemble the estate-wide zitadel outputs -- the
# cutover needs every client id in one place even though the resources now live
# with the service that uses them.
output "zitadel_apps" {
  sensitive = true
  value = {
    "Score/score-web-app" = { kind = "oidc", client_id = zitadel_application_oidc.web.client_id, client_secret = zitadel_application_oidc.web.client_secret }
    "Score/score-api"     = { kind = "api", client_id = zitadel_application_api.api.client_id, client_secret = zitadel_application_api.api.client_secret }
  }
}

output "zitadel_project_id" {
  value = zitadel_project.this.id
}
