# This instance's own Storage Box sub-account -- the credential it reaches the
# repository with. Moved here from ../../hetzner on 2026-09-27: the box is
# estate-level infra, a credential belongs with whatever authenticates using it.
#
# ONE PER INSTANCE, which is what confines the damage. A sub-account cannot see
# outside its home_directory, so samson holding this cannot reach mindy's
# repository, and neither can reach kopia's. That is also why the two restic
# repositories are separate rather than shared.
resource "hcloud_storage_box_subaccount" "this" {
  storage_box_id = var.storage_box_id

  # A LABEL, not the login -- `username` is computed and assigned by Hetzner.
  name           = "backrest-${var.instance}"
  home_directory = "backrest/${var.instance}/"
  description    = "restic repository for the backrest instance on ${var.instance}."

  password = random_password.sftp.result

  access_settings = {
    reachable_externally = false
    samba_enabled        = false
    ssh_enabled          = true
    webdav_enabled       = false
    readonly             = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Hetzner enforces a password policy and rejects the apply otherwise, so the
# min_ values are required rather than defensive.
resource "random_password" "sftp" {
  length           = 32
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!@#%^*()-_=+"
}
