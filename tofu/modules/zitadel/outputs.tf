# What remains here is INSTANCE-LEVEL: the orgs, the SMTP provider, and home
# assistant -- which has no service module because plop is not in tofu yet.
#
# Every other project, role and client now lives with the service that uses it
# (../services/*/auth.tf). The root merges these outputs with theirs so the
# cutover still has every client id in one place:
#
#   tofu output -json zitadel_apps | jq
#
# Secrets are sensitive, so they are redacted in normal output and appear only
# via -json. They are in state either way -- which is encrypted, and why that
# mattered.

output "apps" {
  description = "Client ids and secrets for the apps still owned here."
  sensitive   = true
  value = {
    "home/home assistant" = {
      kind          = "oidc"
      client_id     = zitadel_application_oidc.home_assistant.client_id
      client_secret = zitadel_application_oidc.home_assistant.client_secret
    }
  }
}

output "project_ids" {
  description = "Project ids still owned here."
  value = {
    "home" = zitadel_project.home.id
  }
}

# The orgs are instance-level, not part of any service slice, so they stay here
# and the service modules take the id as a variable.
output "org_home_id" {
  value = zitadel_org.home.id
}
