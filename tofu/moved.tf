# The five Hetzner resources were imported at ROOT addresses on 2026-09-16,
# before this config grew child modules. Moving a resource into a module
# changes its state address, and without these blocks tofu would read that as
# "destroy hcloud_server.bumba, create module.hetzner.hcloud_server.bumba".
#
# `moved` makes it a state operation instead: the plan says "moved", not
# "replaced", and nothing at Hetzner is touched.
#
# Safe to delete once an apply has processed them -- they describe a one-time
# rename, not an ongoing fact. Leaving them costs nothing but noise.

moved {
  from = hcloud_server.bumba
  to   = module.hetzner.hcloud_server.bumba
}

moved {
  from = hcloud_server.mindy
  to   = module.hetzner.hcloud_server.mindy
}

moved {
  from = hcloud_volume.bumba_db
  to   = module.hetzner.hcloud_volume.bumba_db
}

moved {
  from = hcloud_firewall.default
  to   = module.hetzner.hcloud_firewall.default
}

moved {
  from = hcloud_storage_box.backups
  to   = module.hetzner.hcloud_storage_box.backups
}
