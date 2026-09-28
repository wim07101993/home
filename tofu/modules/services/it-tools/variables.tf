variable "traefik_network" {
  type        = string
  description = "traefik's network on mindy. Passed from the reverse-proxy module so this container cannot be created before the network it needs."
}
