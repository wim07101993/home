# keuken.wvl.app. Moved out of reverse-proxy/mindy/dynamic.yml on 2026-09-22.
output "traefik" {
  value = {
    routers = {
      keuken = {
        rule    = "Host(`keuken.wvl.app`)"
        service = "kitchen-owl"
      }
    }
    services = {
      "kitchen-owl" = { loadBalancer = { servers = [{ url = "http://kitchen-owl:8080" }] } }
    }
  }
}
