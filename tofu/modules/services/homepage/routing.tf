# homepage.wvl.app.
output "traefik" {
  value = {
    network = docker_network.traefik.name
    routers = {
      homepage = {
        rule    = "Host(`homepage.wvl.app`)"
        service = "homepage"
      }
    }
    services = {
      homepage = { loadBalancer = { servers = [{ url = "http://homepage:3000" }] } }
    }
  }
}
