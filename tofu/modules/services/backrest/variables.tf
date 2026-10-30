variable "instance" {
  type = string

  description = <<-EOT
    Backrest's instance name, and also the container hostname.
  EOT
}

variable "tailscale_ip" {
  type        = string
  description = "The host's tailnet address. The UI binds to THIS, not 0.0.0.0 -- see main.tf. There is no TLS here and none is needed: the transport is a WireGuard tunnel, the same reasoning providers.tf uses for postgres."
}

variable "port" {
  type = number
}

variable "config_path" {
  type    = string
  default = "/docker-volumes/backrest"
}

# --- where backups go -------------------------------------------------------

variable "repository_password" {
  type        = string
  sensitive   = true
}

variable "storage_box" {
  type = object({
    id   = number
    host = string
    via = optional(object({
      host = string
      port = number
    }))
  })
}

variable "rest_server" {
  type = object({
    name = string
    url  = string
  })
  default = null

  description = <<-EOT
    A restic REST server for a second repository -- samson's, from
    ../rest-server, e.g. { name = "samson", url = "http://<tailnet ip>:8000" }.
    null means the Storage Box only.

    The repository is <url>/<instance>/, and this instance logs in as
    <instance> with the password in rest-server.tf, whose hash the server gets
    through the rest_server_account output.

    Its plan is <instance>-<name>.
  EOT
}

# --- resources --------------------------------------------------------------

variable "backup" {
  type = list(object({
    paths = list(string)
  }))

  description = <<-EOT
    What to back up, contributed by the services that own the data -- the same
    shape as var.routing on the reverse proxy. Each entry is one service's
    `backup` output: the host paths to back up, folders or single files.

    Each is mounted read-only at the same path inside the container, and backed
    up from there. So a path must not be one of backrest's own -- /data,
    /cache, /config, /app -- and the snapshots show the host path. restic
    records the path, so moving one starts its history over.
  EOT

  validation {
    condition = alltrue([for p in flatten(var.backup[*].paths) :
      startswith(p, "/") && !anytrue([for own in ["/data", "/cache", "/config", "/app", "/run"] :
        p == own || startswith(p, "${own}/")
      ])
    ])
    error_message = "Backup paths must be absolute, and not inside the container's own /data, /cache, /config, /app or /run."
  }
}
