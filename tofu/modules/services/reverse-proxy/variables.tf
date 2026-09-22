variable "host" {
  type        = string
  description = "Which host's config directory to upload: `bumba` or `mindy`. The YAML lives in this module, beside the container it configures, one directory per host."

  validation {
    condition     = contains(["bumba", "mindy"], var.host)
    error_message = "host must be bumba or mindy -- there must be a matching directory in this module."
  }
}

variable "container_name" {
  type        = string
  description = "bumba calls it reverse-proxy, mindy calls it traefik. Kept per host so a cutover does not also rename things."
}

# renovate: datasource=docker depName=traefik
variable "image_tag" {
  type        = string
  default     = "v3.7.10"
  description = <<-EOT
    Pinned deliberately at the version bumba runs today, so the cutover changes
    ONE thing. mindy is on v3.7.13; closing that drift is a separate change.

    The `# renovate:` comment above is load-bearing: it is how Renovate finds
    this string. dependabot cannot see an image in HCL at all -- though it never
    saw bumba anyway, since .github/dependabot.yml listed six mindy directories
    and nothing else. See ../../../../renovate.json.
  EOT
}

variable "network_name" {
  type        = string
  default     = "reverse-proxy_reverse-proxy-network"
  description = <<-EOT
    The compose-created name, kept EXACTLY. The zitadel and score stacks stay
    on compose and reference it as `external: true`; renaming it silently
    detaches every service behind this proxy.
  EOT
}

variable "letsencrypt_path" {
  type        = string
  default     = "/docker-volumes/traefik/letsencrypt"
  description = "Bind mount holding acme.json. Certificates survive container recreation because of this -- which is what makes the cutover cheap."
}





# Routing, assembled from the services themselves.
#
# Each service module exposes a `traefik` output holding its own routers,
# services and (rarely) middlewares; the root collects them into this list and
# main.tf merges them into one dynamic.yml. A service missing from the list is
# unreachable -- there is still no auto-discovery, the difference is only WHERE
# the route is written.
# TYPED, which took one iteration to get right. `list(any)` fails outright --
# it unifies its element types, and only file-browser carries a middleware:
#
#   Error: all list elements must have the same type
#
# `optional(..., [])` is what fixes that. It gives every router the same OBJECT
# TYPE whether or not the service wrote `middlewares`, so the elements unify --
# and it documents the shape a service has to produce, which `any` did not.
#
# The middleware DEFINITIONS stay untyped on purpose: buffering, headers,
# rateLimit and the rest share no schema, so a type here would be a lie.
variable "routing" {
  type = list(object({
    routers = map(object({
      rule        = string
      service     = string
      middlewares = optional(list(string), [])
    }))
    services = map(object({
      loadBalancer = object({
        servers = list(object({ url = string }))
      })
    }))
    middlewares = optional(any, {})
  }))
  default     = []
  description = "Per-service traefik fragments, from each service's `traefik` output."
}

variable "dashboard_host" {
  type = string
}
