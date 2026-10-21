variable "tailscale_ip" {
  type        = string
  description = "samson's tailnet address. Navidrome binds HERE and nowhere else; the public route is mindy's traefik, which reaches it over the tailnet."
}

variable "host_port" {
  type = number
}
