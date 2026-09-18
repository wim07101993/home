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

# From module.databases -- see ../score/variables.tf.
variable "db_user" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_name" {
  type = string
}

variable "oidc_client_id" {
  type      = string
  sensitive = true
}

variable "oidc_client_secret" {
  type      = string
  sensitive = true
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
