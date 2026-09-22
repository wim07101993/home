# One firewall, both servers. Not one per host -- `hcloud firewall describe`
# shows it applied to bumba and mindy alike.
#
# This is the only thing keeping bumba's postgres off the internet:
# home-eu-central-1/database/docker-compose.yaml publishes "5432:5432", which
# binds 0.0.0.0. Hetzner default-denies inbound and there is no rule for 5432,
# so it is dropped on both address families. There is no rule for 22 either --
# Tailscale is the only way in.
#
# `durin` per the naming convention in README.md. Was `firewall-1`, Hetzner's
# default. Renaming must plan as an IN-PLACE update -- a replacement would
# detach the firewall from both servers while the new one is created, leaving
# them open on every port for the length of the apply.

resource "hcloud_firewall" "default" {
  name = "durin"

  # NO apply_to HERE. The attachment is declared on the SERVERS (servers.tf,
  # firewall_ids) and only there -- declaring it on both sides is two sources
  # of truth for one fact, and referencing in both directions is a dependency
  # cycle.
  #
  # The servers own it rather than this resource because `firewall_ids`
  # guarantees a server is attached BEFORE ITS FIRST BOOT. Neither apply_to nor
  # hcloud_firewall_attachment does, so both leave a window where a freshly
  # recreated server is briefly reachable on every port.

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    port       = "443"
    protocol   = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    port       = "80"
    protocol   = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  lifecycle {
    # Rule changes are in-place and reversible. Destroying the resource exposes
    # postgres on 5432 the same second.
    prevent_destroy = true
  }
}
