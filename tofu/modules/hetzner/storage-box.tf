resource "hcloud_storage_box" "backups" {
  name             = "snow-white"
  storage_box_type = "bx21"
  location         = "fsn1"
  password         = random_password.storage_box.result

  delete_protection = true
  ssh_keys          = []

  snapshot_plan = {
    max_snapshots = 14
    hour          = 7
    minute        = 0
  }

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
      ssh_keys,
    ]
  }
}

resource "random_password" "storage_box" {
  length           = 32
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!@#%^*()-_=+"
}

# RETAINED AFTER KOPIA WAS REMOVED on 2026-09-29. The kopia containers and the
# module are gone; this sub-account is not, because its home_directory IS the
# repository -- deleting it deletes the backups it holds.
#
# Nothing in tofu reads it any more. Keep it until the restic repositories have
# a full retention window and a restore has actually been tested, then delete it
# deliberately and reclaim the space on the box.
resource "hcloud_storage_box_subaccount" "kopia" {
  storage_box_id = hcloud_storage_box.backups.id

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

resource "random_password" "storage_box_sftp" {
  length           = 32
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!@#%^*()-_=+"
}
