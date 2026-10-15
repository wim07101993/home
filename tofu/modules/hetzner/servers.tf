resource "hcloud_server" "bumba" {
  name        = "bumba"
  server_type = "cpx11" # cpx11 is NOT orderable
  location    = "fsn1"
  image       = "debian-12"

  backups            = false
  delete_protection  = true
  rebuild_protection = true
  firewall_ids       = [hcloud_firewall.default.id]
  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      image,     # debian-12 may stop being offered; it is not re-applied anyway
      ssh_keys,  # forces replacement in the hcloud provider
      user_data, # same
    ]
  }
}

resource "hcloud_server" "mindy" {
  name        = "mindy"
  server_type = "cx43"
  location    = "fsn1"
  image       = "debian-13"

  backups            = true
  delete_protection  = true
  rebuild_protection = true
  firewall_ids       = [hcloud_firewall.default.id]
  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      image,
      ssh_keys,
      user_data,
    ]
  }
}
