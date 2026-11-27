output "traefik" {
  value = {
    network = docker_network.traefik.name
    routers = {
      tasks = {
        rule    = "Host(`${local.host}`)"
        service = "donetick"
      }
    }
    services = {
      donetick = { loadBalancer = { servers = [{ url = "http://donetick:2021" }] } }
    }
  }
}
