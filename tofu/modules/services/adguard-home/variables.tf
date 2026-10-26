variable "host_port" {
  type        = number
  description = "The UI. Also what to enter as the admin interface port in the setup wizard: the container side is fixed at 3000."
}

variable "router_addr" {
  type        = string
  description = "The LAN router. It knows the .home names, and which device has which address."
}

variable "dns_records" {
  type        = map(string)
  default     = {}
  description = "Names AdGuard Home answers itself, name => address. Ahead of the router, which is asked for the rest of .home."
}

variable "dns_port" {
  type        = number
  description = "Always 53 in practice: DHCP clients cannot be told another port."
}
