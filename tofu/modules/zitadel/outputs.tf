# What the cutover needs: each app's new client id, and for confidential apps
# the new secret.
#
#   tofu output -json zitadel_apps | jq
#
# Secrets are sensitive, so they are redacted in normal output and appear only
# via -json. They are in state either way -- which is encrypted, and why that
# mattered.

output "apps" {
  description = "New client ids and secrets, keyed by project/app."
  sensitive   = true

  value = merge(
    { for k, a in {
      "Score/score-web-app"        = zitadel_application_oidc.score_web_app
      "home/home assistant"        = zitadel_application_oidc.home_assistant
      "photos/immich"              = zitadel_application_oidc.immich
      "drive/drive"                = zitadel_application_oidc.drive
      "memo/memo"                  = zitadel_application_oidc.memo
      "keuken/kitchen owl web-app" = zitadel_application_oidc.kitchen_owl_web_app
      "status/gatus"               = zitadel_application_oidc.gatus
      } : k => { kind = "oidc", client_id = a.client_id, client_secret = a.client_secret }
    },
    { for k, a in {
      "Score/score-api" = zitadel_application_api.score_api
      } : k => { kind = "api", client_id = a.client_id, client_secret = a.client_secret }
    },
  )
}

output "project_ids" {
  description = "New project ids -- needed when recreating the 20 user grants."
  value = {
    "Score"  = zitadel_project.score.id
    "home"   = zitadel_project.home.id
    "photos" = zitadel_project.photos.id
    "drive"  = zitadel_project.drive.id
    "keuken" = zitadel_project.keuken.id
    "memo"   = zitadel_project.memo.id
    "status" = zitadel_project.status.id
  }
}
