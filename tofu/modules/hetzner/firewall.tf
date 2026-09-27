resource "hcloud_firewall" "default" {
  name = "durin"

  // allow ping
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  // allow https traffic
  rule {
    direction  = "in"
    port       = "443"
    protocol   = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  // allow http traffic
  rule {
    direction  = "in"
    port       = "80"
    protocol   = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  lifecycle {
    prevent_destroy = true
  }
}
