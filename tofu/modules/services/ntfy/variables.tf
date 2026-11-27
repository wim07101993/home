variable "data_path" {
  type        = string
  default     = "/docker-volumes/ntfy/data"
  description = "Holds the user database and the cached messages. nix/hosts/bumba creates it, owned by the remapped root."
}
