# renovate: datasource=docker depName=tombursch/kitchenowl
variable "image_tag" {
  type    = string
  default = "v0.7.8"
}

variable "traefik_network" {
  type = string
}

variable "db_network" {
  type = string
}

variable "data_path" {
  type        = string
  default     = "/docker-volumes/kitchen-owl/data"
  description = "Uploads and attachments. Unchanged by the database move."
}

variable "host_port" {
  type    = number
  default = 3002
}

# The org this project lives in. Passed from ../../zitadel, which owns the org
# objects -- those are instance-level and not part of any one service.
variable "org_id" {
  type = string
}
