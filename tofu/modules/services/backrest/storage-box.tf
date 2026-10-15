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

resource "random_password" "sftp" {
  length           = 32
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!@#%^*()-_=+"
}
