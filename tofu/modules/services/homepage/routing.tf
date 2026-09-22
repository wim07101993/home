# homepage.wvl.app. Moved out of reverse-proxy/mindy/dynamic.yml on 2026-09-22.
output "traefik" {
  value = {
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
