output "traefik" {
  value = {
    network = docker_network.traefik.name
    routers = {
      ntfy = {
        rule    = "Host(`${local.host}`)"
        service = "ntfy"
      }
    }
    services = {
      ntfy = { loadBalancer = { servers = [{ url = "http://ntfy:8080" }] } }
    }
  }
}
