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

# THE most consequential value in this estate.
#
# Zitadel encrypts every secret in its database with this: IdP client secrets,
# machine keys, the SMTP password, OTP seeds. Change it and none of them can be
# decrypted again -- there is no recovery, only a rebuild from nothing.
#
# It lived ONLY in /docker-volumes/zitadel/zitadel_masterkey on bumba until
# 2026-09-18. Nothing backs bumba up: no cron, no kopia/restic/borg, no Hetzner
# snapshots. One disk, one copy. That is why it is a variable now -- not to
# reduce maintenance (the file is never edited) but so it exists in more than
# one place: secrets.auto.tfvars on a laptop, the encrypted state, and the
# running container.
#
# To populate it WITHOUT putting it on a terminal or in shell history:
#
#   printf 'zitadel_masterkey = "%s"\n' \
#     "$(ssh root@<bumba> cat /docker-volumes/zitadel/zitadel_masterkey)" \
#     >> tofu/secrets.auto.tfvars
#
# It must match the existing key EXACTLY -- 32 bytes, no trailing newline. The
# validation below catches the likely mistakes; it cannot catch a wrong key,
# and a wrong key means zitadel starts and then cannot read its own data.
variable "masterkey" {
  type      = string
  sensitive = true

  validation {
    condition     = length(var.masterkey) == 32
    error_message = "Zitadel's masterkey must be exactly 32 characters. A trailing newline from `cat` is the usual cause of 33."
  }

  validation {
    condition     = var.masterkey == trimspace(var.masterkey)
    error_message = "Zitadel's masterkey has leading or trailing whitespace. The file on disk has none, so this will not match."
  }
}

# From module.databases, which adopted both roles and generates their
# passwords. Retires the hand-maintained zitadel_secrets.yaml on bumba.
variable "db_credentials" {
  type = object({
    user_username  = string
    user_password  = string
    admin_username = string
    admin_password = string
  })
  sensitive = true
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
