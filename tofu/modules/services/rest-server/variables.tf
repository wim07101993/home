variable "tailscale_ip" {
  type        = string
  description = "The host's tailnet address. The server binds to THIS only. Plain HTTP, like backrest's UI: the transport is a WireGuard tunnel, and restic encrypts everything it stores."
}

variable "port" {
  type = number
}

variable "data_path" {
  type        = string
  description = "Where the repositories live on the host. Must exist: docker does not create the source of a bind mount."
}

variable "clients" {
  type = list(object({
    username    = string
    bcrypt_hash = string
  }))
  sensitive = true

  description = <<-EOT
    The hosts that back up here, each one backrest's rest_server_account
    output. The passwords stay with them -- this server only gets the hashes.
    Each sees only its own repository, at /<username>/.
  EOT
}
