# music.wvl.app, apart from navidrome's own paths -- see ../navidrome/routing.tf.
# Rule length is traefik's default priority, so navidrome's longer rule wins for
# those paths and this one takes the rest.
output "traefik" {
  value = {
    network = docker_network.traefik.name
    routers = {
      music-player = {
        rule    = "Host(`music.wvl.app`)"
        service = "feishin"
      }
    }
    services = {
      feishin = { loadBalancer = { servers = [{ url = "http://feishin:9180" }] } }
    }
  }
}
