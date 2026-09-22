# drive.wvl.app. Moved out of reverse-proxy/mindy/dynamic.yml on 2026-09-22.
#
# ROUTER AND MIDDLEWARE SHARE A STEM so they cannot disagree. Under compose they
# were `drive` and `fb-size-limit`, and the middleware was attached to a router
# called `filebrowser` that did not exist -- traefik invented one with a rule of
# Host(`filebrowser-filebrowser`), looped forever on ACME for a hostname with no
# dot, and never applied the limit. Nothing errored.
output "traefik" {
  value = {
    routers = {
      drive = {
        rule        = "Host(`drive.wvl.app`)"
        service     = "filebrowser"
        middlewares = ["drive-size-limit"]
      }
    }
    middlewares = {
      # 2 GB uploads.
      "drive-size-limit" = { buffering = { maxRequestBodyBytes = 2000000000 } }
    }
    services = {
      filebrowser = { loadBalancer = { servers = [{ url = "http://filebrowser:80" }] } }
    }
  }
}
