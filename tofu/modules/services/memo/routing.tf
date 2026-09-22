# memo.wvl.app. Moved out of reverse-proxy/mindy/dynamic.yml on 2026-09-22.
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
