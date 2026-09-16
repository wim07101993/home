# One firewall, both servers. Not one per host -- `hcloud firewall describe`
# shows it applied to bumba and mindy alike.
#
# This is the only thing keeping bumba's postgres off the internet:
# home-eu-central-1/database/docker-compose.yaml publishes "5432:5432", which
# binds 0.0.0.0. Hetzner default-denies inbound and there is no rule for 5432,
# so it is dropped on both address families. There is no rule for 22 either --
# Tailscale is the only way in.

resource "hcloud_firewall" "default" {
  name   = "firewall-1"
  labels = {}

  apply_to {
    label_selector = ""
    server         = 100750341
  }
  apply_to {
    label_selector = ""
    server         = 124902827
  }

  rule {
    description     = ""
    destination_ips = []
    direction       = "in"
    port            = ""
    protocol        = "icmp"
    source_ips      = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description     = ""
    destination_ips = []
    direction       = "in"
    port            = "443"
    protocol        = "tcp"
    source_ips      = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description     = ""
    destination_ips = []
    direction       = "in"
    port            = "80"
    protocol        = "tcp"
    source_ips      = ["0.0.0.0/0", "::/0"]
  }

  lifecycle {
    # Rule changes are in-place and reversible. Destroying the resource exposes
    # postgres on 5432 the same second.
    prevent_destroy = true
  }
}
