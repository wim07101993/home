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
