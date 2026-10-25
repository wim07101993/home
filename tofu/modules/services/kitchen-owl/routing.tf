output "traefik" {
  value = {
    network = docker_network.traefik.name
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
