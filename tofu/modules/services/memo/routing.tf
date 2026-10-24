output "traefik" {
  value = {
    network = docker_network.traefik.name
    routers = {
      memo = {
        rule    = "Host(`memo.wvl.app`)"
        service = "memos"
      }
    }
    services = {
      memos = { loadBalancer = { servers = [{ url = "http://memos:5230" }] } }
    }
  }
}
