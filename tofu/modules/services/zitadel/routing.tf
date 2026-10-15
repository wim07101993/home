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
      zitadel         = { loadBalancer = { servers = [{ url = "h2c://zitadel:8080" }] } }
      "zitadel-login" = { loadBalancer = { servers = [{ url = "http://zitadel-login:3000" }] } }
    }
  }
}
