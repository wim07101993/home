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

variable "api_port" {
  type    = number
  default = 3005
}

variable "web_port" {
  type    = number
  default = 3006
}

# The org this project lives in. Passed from ../../zitadel, which owns the org
# objects -- those are instance-level and not part of any one service.
variable "org_id" {
  type = string
}
