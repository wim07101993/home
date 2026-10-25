# photos.wvl.app.
#
# The backend is the CONTAINER port, not the host-published one.
output "traefik" {
  value = {
    network = docker_network.traefik.name
    routers = {
      photos = {
        rule    = "Host(`photos.wvl.app`)"
        service = "immich"
      }
    }
    services = {
      immich = { loadBalancer = { servers = [{ url = "http://immich:2283" }] } }
    }
  }
}
