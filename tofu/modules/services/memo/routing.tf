output "traefik" {
  value = {
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
