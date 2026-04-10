variable "traefik_network" { type = string }
variable "db_network" { type = string }
variable "domain" { type = string }

variable "user_password" {
  type      = string
  sensitive = true
}

variable "root_password" {
  type      = string
  sensitive = true
}

variable "masterkey" {
  type      = string
  sensitive = true
}
