# it-tools.wvl.app.
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
