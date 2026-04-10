resource "docker_network" "traefik_network" {
  name   = "traefik-network"
  driver = "overlay"
  attachable = true
}

resource "docker_network" "db_network" {
  name   = "db-network"
  driver = "overlay"
  attachable = true
}
