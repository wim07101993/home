# it-tools.wvl.app. Moved out of reverse-proxy/mindy/dynamic.yml on 2026-09-22.
output "traefik" {
  value = {
    routers = {
      "it-tools" = {
        rule    = "Host(`it-tools.wvl.app`)"
        service = "it-tools"
      }
    }
    services = {
      "it-tools" = { loadBalancer = { servers = [{ url = "http://it-tools:80" }] } }
    }
  }
}
