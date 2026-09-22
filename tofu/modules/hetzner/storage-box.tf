# `snow-white`, bx21, fsn1. kopia's off-site repository -- one of the three
# copies of the family photos.
#
# This is the resource that could not be generated: the Cloud API never returns
# the password, so `-generate-config-out` wrote `password = null` and the plan
# refused. It has to be supplied.

resource "hcloud_storage_box" "backups" {
  name             = "snow-white"
  storage_box_type = "bx21"
  location         = "fsn1"
  password         = random_password.storage_box.result

  # Hetzner-side protection: blocks deletion from the API and the Cloud Console,
  # not just from tofu. `prevent_destroy` below only stops tofu.
  #
  # Was false because import captured whatever the console had -- the volume
  # happened to have it on and this did not. The asymmetry ran the wrong way:
  # a storage box holding every backup was less protected than a 100 GB volume.
  #
  # Cost: a real teardown becomes two applies -- flip this, then destroy.
  delete_protection = true
  ssh_keys          = []

  access_settings = {
    reachable_externally = false
    samba_enabled        = false
    ssh_enabled          = true
    webdav_enabled       = false
    zfs_enabled          = false
  }

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      # ssh_keys is the dangerous one, and not theoretically: provider v1.58.0
      # changed it from ignored to replacement-forcing. The Hetzner API has no
      # update path for those keys, so the provider's only way to reconcile a
      # difference is destroy-and-recreate -- which would take the off-site
      # kopia repository with it.
      ssh_keys,

      # `password` was here too, because the API never returns it and tofu could
      # not tell a stale config value from the live one. That ended when tofu
      # became the only writer -- see random_password.storage_box below.
    ]
  }
}

# GENERATED, and tofu is the only writer.
#
# It was adopted with ignore_changes = all while the real value lived in
# Bitwarden. That is no longer needed: `password` carries no RequiresReplace
# (unlike `ssh_keys` on the same resource) and Update calls the Storage Box
# ResetPassword action, so a change is an in-place rotation and not a rebuild of
# the box holding every backup.
#
# NOT the credential kopia uses. That is the sub-account below. This is the MAIN
# account: Cloud Console login, SMB, and SSH as u643732.
#
# The API never returns it, so the output is the only way to read it back:
#
#   tofu output -raw storage_box_password
#
# The min_ values are REQUIRED, not defensive. Hetzner enforces a password
# policy and rejects the whole apply otherwise:
#
#   invalid input in field password (invalid_input) 422
#   The password must contain at least one upper case letter, one lower case
#   letter, one number, and a special character
#
# random_password only guarantees a class is PRESENT if a min_ is set for it --
# by default it merely permits them, so a generated value can legitimately
# contain none and fail this intermittently, at apply time.
resource "random_password" "storage_box" {
  length           = 32
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!@#%^*()-_=+"
}

# The sub-account kopia connects as. ADOPTED (created by hand in the Cloud
# Console), with its password now generated.
#
# kopia reaches it as sftp://u643732-sub1@... with path "backup", which is
# RELATIVE TO home_directory -- so the repository lives at backup/backup on the
# box. home_directory is Required but NOT replace-forcing: a wrong value moves
# the directory rather than destroying the sub-account, which is visible in the
# plan and recoverable, but it would take kopia's repository with it.
#
# Imported as "<storage_box_id>/<subaccount_id>", e.g. 625908/281501.
resource "hcloud_storage_box_subaccount" "kopia" {
  storage_box_id = hcloud_storage_box.backups.id

  # A LABEL, not the login. `username` is computed and assigned by Hetzner
  # (u643732-sub1); kopia authenticates with that and is unaffected by this.
  # It defaulted to the username, which made the two look like one field.
  #
  # Pinned rather than omitted: `name` is Optional+Computed, so leaving it out
  # shows "known after apply" on every plan.
  name           = "kopia"
  home_directory = "backup/"
  description    = "Repository target for the kopia server on mindy."

  password = random_password.storage_box_sftp.result

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

# GENERATED. Same policy minimums as the main account -- see above.
#
# Rotating this recreates the kopia container, because its repository.config is
# generated from this value. Both happen in one apply.
resource "random_password" "storage_box_sftp" {
  length           = 32
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!@#%^*()-_=+"
}
