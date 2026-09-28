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
