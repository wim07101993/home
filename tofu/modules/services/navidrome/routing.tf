# Only navidrome's own paths on music.wvl.app. The rest, `/` included, is
# feishin -- see ../feishin/routing.tf. Navidrome's UI stays at /app/, for
# admin work; the apps use /rest.
output "traefik" {
  value = {
    routers = {
      music = {
        rule    = "Host(`music.wvl.app`) && (PathPrefix(`/app`) || PathPrefix(`/api`) || PathPrefix(`/auth`) || PathPrefix(`/rest`) || PathPrefix(`/share`) || PathPrefix(`/jellyfin`) || Path(`/ping`))"
        service = "navidrome"
      }
    }
    services = {
      navidrome = { loadBalancer = { servers = [{ url = "http://${var.tailscale_ip}:${var.host_port}" }] } }
    }
  }
}
