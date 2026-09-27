resource "hcloud_volume" "data" {
  name     = "rafiki"
  location = "fsn1"
  size     = 100

  delete_protection = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_volume_attachment" "data" {
  volume_id = hcloud_volume.data.id
  server_id = hcloud_server.mindy.id
}
