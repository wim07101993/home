variable "user" {
  type    = string
  default = "wim"
}

variable "uid" {
  type        = number
  default     = 1000
  description = "Owner of uploaded files on the host. With host user namespaces this is the real uid -- wim, like the rest of the media library."
}

variable "gid" {
  type        = number
  default     = 100
  description = "users, which owns the media library and has write access to it."
}

variable "media_path" {
  type = string
}

variable "passive_ports" {
  type = object({
    from = number
    to   = number
  })
  default = { from = 21000, to = 21010 }

  description = "Fixed in nix/hosts/samson/default.nix too, where the firewall opens them alongside 21."
}
