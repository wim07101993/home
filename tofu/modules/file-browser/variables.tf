variable "traefik_network" { type = string }
variable "db_network" { type = string }
variable "domain" { type = string }
variable "zitadel_org_id" { type = string }
variable "zitadel_project_id" { type = string }

variable "db_password" {
  type      = string
  sensitive = true
}


