# score.wvl.app, partituren.wvl.app and score-api.wvl.app. Moved out of
# reverse-proxy/mindy/dynamic.yml on 2026-09-22.
#
# TWO HOSTNAMES, ONE BACKEND: `score` and `partituren` both point at
# score-web-app. That is why the routers and the services are separate maps --
# a router per hostname, a service per backend.
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
