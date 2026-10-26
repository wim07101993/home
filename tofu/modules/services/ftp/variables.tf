variable "user" {
  type    = string
  default = "wim"
}

variable "uid" {
  type        = number
  default     = 951
  description = "Owner of uploaded files on the host. With host user namespaces this is the real uid -- ftp-media in nix/hosts/samson/default.nix, not wim."
}

variable "gid" {
  type        = number
  default     = 951
  description = "media, which owns the media library and has write access to it; wim is a member."
}

variable "media_path" {
  type = string
}

variable "audio_archive_path" {
  type        = string
  description = "Its group is users; gid writes it through an ACL that nix/hosts/samson/default.nix keeps."
}

variable "passive_ports" {
  type = object({
    from = number
    to   = number
  })
  default = { from = 21000, to = 21010 }

  description = "Fixed in nix/hosts/samson/default.nix too, where the firewall opens them alongside 21."
}
