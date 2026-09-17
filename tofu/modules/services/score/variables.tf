# renovate: datasource=docker depName=wim07101993/score
variable "api_image_tag" {
  type    = string
  default = "v0.6.0"
}

# renovate: datasource=docker depName=wim07101993/score-frontend
variable "web_image_tag" {
  type    = string
  default = "v0.6.0"
}

variable "traefik_network" {
  type = string
}

variable "db_network" {
  type = string
}

variable "api_client_id" {
  type        = string
  sensitive   = true
  description = "zitadel_application_api.score_api.client_id -- used by the API to introspect tokens."
}

variable "api_client_secret" {
  type      = string
  sensitive = true
}

variable "web_client_id" {
  type        = string
  sensitive   = true
  description = <<-EOT
    zitadel_application_oidc.score_web_app.client_id.

    This MUST match the project the API checks roles against. The frontend
    obtains the token; the API introspects it and looks for
    urn:zitadel:iam:org:project:roles. Point them at apps in different projects
    and every request is authenticated and then refused.
  EOT
}

variable "api_port" {
  type    = number
  default = 3005
}

variable "web_port" {
  type    = number
  default = 3006
}
