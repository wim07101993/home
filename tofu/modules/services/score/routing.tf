output "traefik" {
  value = {
    routers = {
      "score-api" = {
        rule    = "Host(`score-api.wvl.app`)"
        service = "score-api"
      }
      score = {
        rule    = "Host(`score.wvl.app`)"
        service = "score-web-app"
      }
      partituren = {
        rule    = "Host(`partituren.wvl.app`)"
        service = "score-web-app"
      }
    }
    services = {
      "score-api"     = { loadBalancer = { servers = [{ url = "http://score-api:7001" }] } }
      "score-web-app" = { loadBalancer = { servers = [{ url = "http://score-web-app:80" }] } }
    }
  }
}
