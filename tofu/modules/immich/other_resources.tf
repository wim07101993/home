resource "docker_network" "immich_internal" {
  name   = "immich-internal"
  driver = "overlay"
}

