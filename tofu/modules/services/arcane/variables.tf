variable "tailscale_ip" {
  type        = string
  description = "plop's tailnet address. Arcane binds HERE and nowhere else, and it is the host in the OIDC redirect URI."
}

variable "host_port" {
  type = number
}

variable "zitadel_org_id" {
  type = string
}

variable "oidc_issuer_url" {
  type    = string
  default = "https://auth.wvl.app"
}
