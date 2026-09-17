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
