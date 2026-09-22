# Adopted 2026-09-16. Attribute values come from `tofu plan
# -generate-config-out`, i.e. read from the live API -- not transcribed by hand.
#
# Nothing here may be "tidied" BLIND. The config must match reality exactly so
# that `tofu plan` reports "No changes"; anything you would rather were
# different is a deliberate change to make afterwards, on purpose, reading the
# diff.
#
# On 2026-09-22 the generator's null/empty/zero literals were removed -- they
# equal the provider defaults, so omitting them is not a change. That was
# verified by plan, not assumed. The same rule still applies to anything with a
# real value.

resource "hcloud_server" "bumba" {
  name        = "bumba"
  server_type = "cpx11"
  location    = "fsn1"
  image       = "debian-12"

  backups = false
  # Hetzner-side protection: blocks deletion from the API and the Cloud Console,
  # not just from tofu. `prevent_destroy` below only stops tofu.
  #
  # Was false because import captured whatever the console had. The volume
  # happened to have it on and these did not; nobody chose that.
  #
  # Cost: a real teardown becomes two applies -- flip this, then destroy.
  delete_protection = true
  # MUST match delete_protection. Hetzner rejects the apply otherwise:
  #
  #   'delete' and 'rebuild' field required to be the same value (invalid_input)
  #
  # They are one protection object in the API, exposed as two attributes here.
  # No loss: a rebuild wipes the root disk, which for bumba is zitadel's
  # masterkey file and its postgres data -- the same blast radius as deletion.
  rebuild_protection = true
  # THE firewall attachment, and the only declaration of it -- hcloud_firewall
  # deliberately carries no apply_to. Here rather than there because this
  # attaches the firewall before the server's first boot; apply_to does not.
  #
  # Was the literal [10051212].
  firewall_ids = [hcloud_firewall.default.id]
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

  backups = true
  # Hetzner-side protection: blocks deletion from the API and the Cloud Console,
  # not just from tofu. `prevent_destroy` below only stops tofu.
  #
  # Was false because import captured whatever the console had. The volume
  # happened to have it on and these did not; nobody chose that.
  #
  # Cost: a real teardown becomes two applies -- flip this, then destroy.
  delete_protection = true
  # MUST match delete_protection. Hetzner rejects the apply otherwise:
  #
  #   'delete' and 'rebuild' field required to be the same value (invalid_input)
  #
  # They are one protection object in the API, exposed as two attributes here.
  # No loss: a rebuild wipes the root disk, which for bumba is zitadel's
  # masterkey file and its postgres data -- the same blast radius as deletion.
  rebuild_protection = true
  # THE firewall attachment, and the only declaration of it -- hcloud_firewall
  # deliberately carries no apply_to. Here rather than there because this
  # attaches the firewall before the server's first boot; apply_to does not.
  #
  # Was the literal [10051212].
  firewall_ids = [hcloud_firewall.default.id]
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
