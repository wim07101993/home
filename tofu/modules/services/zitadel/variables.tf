# renovate: datasource=docker depName=ghcr.io/zitadel/zitadel
variable "image_tag" {
  type        = string
  default     = "v4.17.3"
  description = <<-EOT
    Used for BOTH images. zitadel and zitadel-login are released together, and
    ghcr.io/zitadel/zitadel-login publishes the same version tags.

    The login image was on `latest` until 2026-09-18 -- unpinned, on the
    component that renders every login page, where a redeploy could pull a
    breaking version with nothing recording which one had been working.
  EOT
}

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

variable "zitadel_port" {
  type    = number
  default = 3001
}

variable "login_port" {
  type    = number
  default = 3002
}

# This zitadel instance's own ID, for the System API user's IAM membership.
#
#   docker exec <postgres> psql -U postgres -d zitadel \
#     -tAc "select id, name from projections.instances"
#
# Not discoverable from the provider: it is needed to BUILD the credential the
# provider authenticates with.
variable "instance_id" {
  type    = string
  default = "340576542272782341"
}
