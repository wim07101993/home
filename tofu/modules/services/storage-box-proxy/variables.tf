variable "target_host" {
  type        = string
  description = "The Storage Box FQDN. Resolved inside the container, on bumba -- which is what makes the connection originate in Hetzner."
}

variable "tailscale_ip" {
  type        = string
  description = "bumba's tailnet address. The listener binds HERE and nowhere else -- bound to 0.0.0.0 this would be an open relay into a Storage Box that only trusts where the packet came from."
}

variable "listen_port" {
  type = number
}
