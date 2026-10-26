variable "tailscale_ip" {
  type        = string
  description = "plop's tailnet address. The UI binds HERE and nowhere else; DNS binds everywhere."
}

variable "host_port" {
  type        = number
  description = "The UI. Also what to enter as the admin interface port in the setup wizard: the container side is fixed at 3000."
}

variable "dns_port" {
  type        = number
  description = "Always 53 in practice: DHCP clients cannot be told another port."
}
