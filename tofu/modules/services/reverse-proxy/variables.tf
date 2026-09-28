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
