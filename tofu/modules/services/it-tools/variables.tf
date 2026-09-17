# renovate: datasource=docker depName=corentinth/it-tools
variable "image_tag" {
  type    = string
  default = "2024.10.22-7ca5933"
  # Nearly two years old. Not changed here, because a cutover should change one
  # thing -- but it is exactly what Renovate exists to surface.
}

variable "network_name" {
  type        = string
  description = "traefik's network on mindy. Passed from the reverse-proxy module so this container cannot be created before the network it needs."
}

variable "host_port" {
  type        = number
  default     = 3000
  description = "Published for direct access; traefik reaches it on the docker network, not through this."
}
