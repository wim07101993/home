# drive.wvl.app.
#
# ROUTER AND MIDDLEWARE SHARE A STEM so they cannot disagree. Under compose they
# were `drive` and `fb-size-limit`, and the middleware was attached to a router
# called `filebrowser` that did not exist -- traefik invented one with a rule of
# Host(`filebrowser-filebrowser`), looped forever on ACME for a hostname with no
# dot, and never applied the limit. Nothing errored.
output "traefik" {
  value = {
    network = docker_network.traefik.name
    routers = {
      drive = {
        rule        = "Host(`drive.wvl.app`)"
        service     = "filebrowser"
        middlewares = ["drive-size-limit"]
      }

      # The PDF preview is the browser's own viewer in an iframe on an inline
      # download, which filebrowser serves with `script-src 'none'` against SVG
      # scripts. Chromium's viewer does not start under that policy and leaves the
      # frame blank. Rule length is traefik's default priority, so this wins over
      # `drive` for exactly these requests.
      drive-inline-pdf = {
        rule        = "Host(`drive.wvl.app`) && Path(`/api/resources/download`) && Query(`inline`, `true`) && QueryRegexp(`file`, `(?i)\\.pdf$`)"
        service     = "filebrowser"
        middlewares = ["drive-inline-pdf"]
      }
    }
    middlewares = {
      # 2 GB uploads.
      "drive-size-limit" = { buffering = { maxRequestBodyBytes = 2000000000 } }

      # An empty value removes the header.
      "drive-inline-pdf" = { headers = { customResponseHeaders = { "Content-Security-Policy" = "" } } }
    }
    services = {
      filebrowser = { loadBalancer = { servers = [{ url = "http://filebrowser:80" }] } }
    }
  }
}
