# Root variables. Everything here comes from the environment via env.sh.

# Read by the `encryption` block, which OpenTofu evaluates before the resource
# graph exists -- hence an environment variable and not a tfvars file.
variable "state_passphrase" {
  type        = string
  sensitive   = true
  description = "State encryption passphrase, 16+ chars. TF_VAR_state_passphrase."
}

# One address, used by both the postgresql provider and the docker provider.
variable "bumba_addr" {
  type        = string
  description = "bumba's TAILNET address. Never the public IP: postgres runs sslmode=disable and relies on WireGuard for transport security."
}

variable "pg_superuser_password" {
  type        = string
  sensitive   = true
  description = "postgres superuser password, from /docker-volumes/db/db_password.txt on bumba."
}

variable "mindy_addr" {
  type        = string
  description = "mindy's TAILNET address."
}

variable "samson_addr" {
  type        = string
  description = "samson's TAILNET address. Reached as root over SSH for the docker provider, like the other two hosts."
}

variable "plop_addr" {
  type        = string
  description = "plop's TAILNET address. Home Assistant and the Matter server; reached as root over SSH for the docker provider."
}

variable "pg_superuser_password_mindy" {
  type        = string
  sensitive   = true
  description = "postgres superuser password on MINDY, from /docker-volumes/db/db_password.txt there. Different file and different value from bumba's."
}

variable "immich_pg_superuser_password" {
  type      = string
  sensitive = true

  description = <<-EOT
    postgres superuser password on IMMICH'S OWN postgres (mindy:5434), a
    different cluster from the shared one above.

    Supplied rather than generated: it configures the postgresql.immich
    provider, and a provider is configured at PLAN time, where a generated
    value is still unknown. Tried on 2026-09-23 and the plan failed with
    `password authentication failed for user "postgres"`.

    Unlike the other two, this one is ENFORCED. The container re-applies it on
    every start -- modules/services/immich/assert-superuser-password.sh -- so
    changing it here and applying is the whole rotation. No manual ALTER.
  EOT
}

# --- kopia ----------------------------------------------------------------
#
# ONLY the repository password is supplied now. The SFTP sub-account password
# moved into modules/hetzner as an adopted random_password (2026-09-19).
#
# This one DELIBERATELY did not move. It encrypts the repository: lose it and
# every backup is unreadable, with no reset. Holding it only in tofu state --
# which is itself encrypted with TF_VAR_state_passphrase -- would mean losing
# that passphrase also loses the backups, which are exactly what you reach for
# when something has gone badly wrong. An independent copy in the vault is what
# keeps that recoverable. Same reasoning applies to TF_VAR_zitadel_masterkey.
#
# Extract it from mindy without displaying it:
#
#   printf 'kopia_repository_password = "%s"\n' \
#     "$(ssh root@<mindy> cat /docker-volumes/kopia/repository_password.txt)" \
#     >> secrets.auto.tfvars
variable "kopia_repository_password" {
  type      = string
  sensitive = true
}

# --- mailgun --------------------------------------------------------------
#
# Replaces the hand-typed gatus SMTP password: tofu now CREATES that credential
# (modules/mailgun) and hands it straight to gatus, so the only mail secret
# left is this key. One key mints as many credentials as services need, and
# rotating one is `tofu taint` plus an apply.
#
# Scope it in the Mailgun console -- it can manage the whole account.
variable "mailgun_api_key" {
  type      = string
  sensitive = true
}
