variable "tailscale_ip" {
  type        = string
  description = "plop's tailnet address: the host in APP_URL and in one of the OIDC redirect URIs."
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
