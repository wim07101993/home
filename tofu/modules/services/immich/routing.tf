# photos.wvl.app. Moved out of reverse-proxy/mindy/dynamic.yml on 2026-09-22.
#
# The backend is the CONTAINER port, not the host-published one.
output "traefik" {
  value = {
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
