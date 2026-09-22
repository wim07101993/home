# status.wvl.app, on BUMBA. Moved out of reverse-proxy/bumba/dynamic.yml on
# 2026-09-22.
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
