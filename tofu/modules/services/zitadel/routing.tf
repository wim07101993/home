# auth.wvl.app, on BUMBA. Moved out of reverse-proxy/bumba/dynamic.yml on
# 2026-09-22.
#
# THE TWO HALVES OF auth.wvl.app. The !PathPrefix on the first is the only thing
# keeping both from matching the same request.
output "traefik" {
  value = {
    routers = {
      zitadel = {
        rule    = "Host(`auth.wvl.app`) && !PathPrefix(`/ui/v2/login`)"
        service = "zitadel"
      }
      "zitadel-login" = {
        rule    = "Host(`auth.wvl.app`) && PathPrefix(`/ui/v2/login`)"
        service = "zitadel-login"
      }
    }
    services = {
      # h2c, NOT http. Zitadel serves gRPC and HTTP on the same port, and gRPC
      # needs HTTP/2 end to end. With plain `http://` traefik speaks HTTP/1.1 to
      # the backend and a gRPC call comes back as "Unimplemented ... 404 ...
      # content-type application/json".
      #
      # The browser console never noticed because it uses gRPC-web, which works
      # over HTTP/1.1. The terraform provider uses native gRPC and does not.
      zitadel         = { loadBalancer = { servers = [{ url = "h2c://zitadel:8080" }] } }
      "zitadel-login" = { loadBalancer = { servers = [{ url = "http://zitadel-login:3000" }] } }
    }
  }
}
