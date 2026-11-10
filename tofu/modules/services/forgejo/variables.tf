variable "tailscale_ip" {
  type        = string
  description = "plop's tailnet address. Forgejo binds HERE and nowhere else, and builds its clone URLs from it."
}

variable "host_port" {
  type = number
}
