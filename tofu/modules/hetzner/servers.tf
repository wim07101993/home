# Adopted 2026-09-16. Attribute values come from `tofu plan
# -generate-config-out`, i.e. read from the live API -- not transcribed by hand.
#
# Nothing here may be "tidied". The config must match reality exactly so that
# `tofu plan` reports "No changes"; anything you would rather were different is
# a deliberate change to make afterwards, on purpose, reading the diff.

resource "hcloud_server" "bumba" {
  name        = "bumba"
  server_type = "cpx11"
  location    = "fsn1"
  image       = "debian-12"

  backups                    = false
  delete_protection          = false
  rebuild_protection         = false
  firewall_ids               = [10051212]
  ignore_remote_firewall_ids = null
  placement_group_id         = 0
  labels                     = {}

  iso                      = null
  keep_disk                = null
  rescue                   = null
  shutdown_before_deletion = null
  ssh_keys                 = null
  user_data                = null

  lifecycle {
    # cpx11 is NOT orderable in fsn1 as of 2026-09-16 -- `hcloud server-type
    # list` shows the whole cpx*1 line in ash and hil only. A replacement plan
    # would destroy successfully and then fail to create, taking Zitadel, the
    # database and this layer's own state backend with it.
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

  backups                    = true
  delete_protection          = false
  rebuild_protection         = false
  firewall_ids               = [10051212]
  ignore_remote_firewall_ids = null
  placement_group_id         = 0
  labels                     = {}

  iso                      = null
  keep_disk                = null
  rescue                   = null
  shutdown_before_deletion = null
  ssh_keys                 = null
  user_data                = null

  lifecycle {
    # cx43 IS still orderable in fsn1, so this one is recoverable in principle.
    # Guarded anyway: the disk is what would not come back.
    prevent_destroy = true

    ignore_changes = [
      image,
      ssh_keys,
      user_data,
    ]
  }
}
