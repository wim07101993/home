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
    ignore_changes  = [
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

# --- backrest ---------------------------------------------------------------
#
resource "hcloud_storage_box_subaccount" "backrest" {
  for_each = toset(["mindy", "samson"])

  storage_box_id = hcloud_storage_box.backups.id

  name           = "backrest-${each.key}"
  home_directory = "backrest/${each.key}/"
  description    = "restic repository for the backrest instance on ${each.key}."

  password = random_password.storage_box_backrest[each.key].result

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

resource "random_password" "storage_box_backrest" {
  for_each = toset(["mindy", "samson"])

  length           = 32
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!@#%^*()-_=+"
}
