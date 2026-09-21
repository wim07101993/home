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

  delete_protection = false
  labels            = {}
  snapshot_plan     = null
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

      # The API never returns it, so tofu cannot tell whether the value in
      # state matches the live one. Without this, a wrong or stale value in
      # random_password.storage_box would silently RESET the real password on
      # the next apply. Rotate in the Cloud Console, not here -- tofu REMEMBERS
      # this password, it does not enforce it.
      password,
    ]
  }
}

# ADOPTED, NOT GENERATED. Imported with the existing value:
#
#   tofu import 'module.hetzner.random_password.storage_box' "$(bw get password 'hetzner snow white user')"
#
# `ignore_changes = all` is what makes that safe. An imported random_password
# takes the provider's DEFAULT generation attributes, so a config that says
# length = 32 against a value of a different length plans a REPLACEMENT -- which
# for this resource means silently minting a new password. Every attribute here
# is nominal; the value comes from the import and must never change.
resource "random_password" "storage_box" {
  length = 32

  lifecycle {
    ignore_changes = all
  }
}

# The sub-account kopia connects as (u643732-sub1), created by hand in the Cloud
# Console. Only the PASSWORD is held here; the sub-account itself is still
# unmanaged.
#
# It could be adopted -- hcloud_storage_box_subaccount exists and supports
# import -- and then `password` being a required attribute would make tofu
# ENFORCE this value rather than merely remember it. Not done here because
# adopting it also brings home_directory and access_settings under management,
# and a mismatch there reconfigures a live backup target.
# ADOPTED, NOT GENERATED. Imported with the existing value:
#
#   tofu import 'module.hetzner.random_password.storage_box_sftp' "$(bw get password 'snow-white ssh subaccount password')"
#
# `ignore_changes = all` is what makes that safe. An imported random_password
# takes the provider's DEFAULT generation attributes, so a config that says
# length = 32 against a value of a different length plans a REPLACEMENT -- which
# for this resource means silently minting a new password. Every attribute here
# is nominal; the value comes from the import and must never change.
resource "random_password" "storage_box_sftp" {
  length = 32

  lifecycle {
    ignore_changes = all
  }
}
