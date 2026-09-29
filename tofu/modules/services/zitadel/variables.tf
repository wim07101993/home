variable "traefik_network" {
  type = string
}

variable "db_network" {
  type        = string
  description = "bumba's postgres network. Zitadel reaches it as `db`."
}

variable "config_path" {
  type        = string
  default     = "/docker-volumes/zitadel"
  description = <<-EOT
    Host directory holding what tofu does NOT manage:

      init-steps.yaml         bootstrap; contains the initial admin password
      login-client/           zitadel WRITES login-client.pat here on first
                              init, and zitadel-login reads it

    Both either hold a secret or are written by the container, so they stay
    host files. This repository is public.

    zitadel_secrets.yaml USED to be here too. It is generated now -- see the
    upload in main.tf. The stale file is left on disk deliberately: until the
    cutover is verified it is the rollback.

    init-steps.yaml is bootstrap-only and has been a no-op since the instance
    was created in 2025, which is the only reason it is tolerable as an
    unversioned host file holding the original admin password.
  EOT
}

variable "host_port" {
  type = number
}

variable "login_host_port" {
  type = number
}
