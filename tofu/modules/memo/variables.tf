variable "traefik_network" {
  type = string
}

variable "db_network" {
  type = string
}

variable "domain" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

