# renovate: datasource=docker depName=kopia/kopia
variable "image_tag" {
  type    = string
  default = "0.23.1"
}

variable "tailscale_ip" {
  type        = string
  description = <<-EOT
    mindy's tailnet address. The repository API binds to THIS, not 0.0.0.0.

    It was "51515:51515" once, which bound mindy's public interface and -- with
    --insecure at the time -- served the repository API over cleartext HTTP to
    the internet. The port is the one remote clients (samson) connect to.
  EOT
}

variable "config_path" {
  type        = string
  default     = "/docker-volumes/kopia"
  description = <<-EOT
    Host directory holding what tofu does not manage:

      kopia-config/     repository.config -- the SFTP target, plus the TLS
                        cert and key the server presents
      kopia-cache/      rebuildable
      repository_password.txt  } the repository password and the server user
      user_password.txt        } password. Read by the entrypoint, never env.
      data/             nine NFS mounts from samson, read-only

    The two password files are the reason this host is the only one that can
    reach the Storage Box. Remote machines connect here as repository CLIENTS
    with a per-machine server user and never learn the repository password.
  EOT
}

variable "server_username" {
  type    = string
  default = "wim"
}

variable "port" {
  type    = number
  default = 51515
}

# --- the repository connection, now generated ------------------------------

variable "repository_password" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Unlocks the repository itself. NOT the Storage Box credential below, and
    NOT the same as var.storage_box_password in the root -- that one is the
    Storage Box MAIN account; kopia connects as a sub-account.

    Written to repository_password.txt for the entrypoint to read. Losing it
    makes every backup unreadable: the repository is encrypted with it.
  EOT
}

variable "sftp_password" {
  type        = string
  sensitive   = true
  description = "Password for the Storage Box SUB-account below."
}

variable "sftp_username" {
  type    = string
  default = "u643732-sub1"
}

variable "sftp_host" {
  type    = string
  default = "u643732.your-storagebox.de"
}

variable "sftp_port" {
  type        = number
  default     = 23
  description = "Hetzner's extended SSH service, which is also what makes Borg a first-class option on Storage Boxes."
}

variable "sftp_path" {
  type    = string
  default = "backup"
}

# THE IDENTITY. Do not tidy these.
#
# Kopia keys every source as <username>@<hostname>:<path>, and it takes those
# from THIS FILE, not from the container's hostname. The values below were
# written when the container ID was the hostname -- which is the exact bug the
# module's `hostname = "mindy"` was meant to fix, and did not, because the
# config file wins.
#
# They are ugly and they are load-bearing. Changing either mints a NEW identity:
# every existing snapshot stays in the repository but becomes invisible to this
# client, and every source restarts from zero history. That is the 2026-08
# finding -- 57 of 65 sources holding exactly one snapshot -- reproduced on
# purpose.
#
# Renaming them is a migration, not an edit.
variable "repository_hostname" {
  type    = string
  default = "1da0a4624124"
}

variable "repository_username" {
  type    = string
  default = "root"
}
