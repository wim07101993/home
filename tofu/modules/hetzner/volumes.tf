resource "hcloud_volume" "bumba_db" {
  name      = "volume-fsn1-1"
  location  = "fsn1"
  size      = 100
  server_id = 100750341

  delete_protection = true
  automount         = null
  format            = null
  labels            = {}

  lifecycle {
    # Carries bumba's postgres, reached through
    # /docker-volumes/db/data -> /mnt/HC_Volume_103225027/db/data/
    # -- which now includes this layer's own state.
    prevent_destroy = true
  }
}
