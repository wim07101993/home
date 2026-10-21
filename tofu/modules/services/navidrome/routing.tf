output "traefik" {
  value = {
    routers = {
      music = {
        rule    = "Host(`music.wvl.app`)"
        service = "navidrome"
      }
    }
    services = {
      navidrome = { loadBalancer = { servers = [{ url = "http://${var.tailscale_ip}:${var.host_port}" }] } }
    }
  }
}
