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
  password         = var.storage_box_password

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
      # TF_VAR_storage_box_password would silently RESET the real password on
      # the next apply. Rotate in the Cloud Console, not here.
      password,
    ]
  }
}
