# status.wvl.app, on BUMBA.
output "traefik" {
  value = {
    routers = {
      status = {
        rule    = "Host(`status.wvl.app`)"
        service = "gatus"
      }
    }
    services = {
      gatus = { loadBalancer = { servers = [{ url = "http://gatus:8080" }] } }
    }
  }
}
