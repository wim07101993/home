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

# Passed down to modules/hetzner. hcloud_storage_box takes `password` as a
# REQUIRED argument and the Cloud API never returns it, so config generation
# cannot fill it in and tofu cannot verify it -- which is why that resource
# also ignores changes to it.
variable "storage_box_password" {
  type        = string
  sensitive   = true
  description = "Storage Box password. TF_VAR_storage_box_password."
}


variable "zitadel_pat" {
  type        = string
  sensitive   = true
  description = "PAT for the `terraform` service user (IAM_OWNER). TF_VAR_zitadel_pat."
}

variable "mindy_addr" {
  type        = string
  description = "mindy's TAILNET address."
}

variable "pg_superuser_password_mindy" {
  type        = string
  sensitive   = true
  description = "postgres superuser password on MINDY, from /docker-volumes/db/db_password.txt there. Different file and different value from bumba's."
}

variable "immich_db_password" {
  type        = string
  sensitive   = true
  description = <<-EOT
    immich's EXISTING postgres password -- not generated. Its cluster is
    already initialised, and changing POSTGRES_PASSWORD on an initialised
    cluster changes nothing except immich's ability to connect.

      ssh root@<mindy> docker inspect immich_postgres \
        | jq -r '.[0].Config.Env[]|select(startswith("POSTGRES_PASSWORD"))|split("=")[1]'
  EOT
}

# --- kopia ----------------------------------------------------------------
#
# TWO different credentials, and neither is var.storage_box_password above --
# that one is the Storage Box MAIN account; kopia connects as a sub-account.
#
#   kopia_repository_password  encrypts the repository. Lose it and every
#                              backup is unreadable. There is no reset.
#   kopia_sftp_password        the Storage Box sub-account, how kopia reaches
#                              the bytes at all.
#
# Extract them from mindy without displaying them:
#
#   printf 'kopia_repository_password = "%s"\n' \
#     "$(ssh root@<mindy> cat /docker-volumes/kopia/repository_password.txt)" \
#     >> secrets.auto.tfvars
#
# The SFTP one is inside repository.config:
#
#   ssh root@<mindy> 'python3 -c "import json;print(json.load(open(\"/docker-volumes/kopia/kopia-config/repository.config\"))[\"storage\"][\"config\"][\"password\"])"'
variable "kopia_repository_password" {
  type      = string
  sensitive = true
}

variable "kopia_sftp_password" {
  type      = string
  sensitive = true
}

# --- zitadel --------------------------------------------------------------
#
# The masterkey. Zitadel encrypts every secret in its database with it, and a
# wrong or lost value is unrecoverable -- there is no reset, only a rebuild.
#
# It is a variable because until 2026-09-18 it existed only on bumba's disk, and
# nothing backs bumba up. See modules/services/zitadel/variables.tf for how to
# populate it without putting it through a terminal.
variable "zitadel_masterkey" {
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
