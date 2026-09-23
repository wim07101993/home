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

variable "photos_path" {
  type        = string
  description = <<-EOT
    The photo library, on mindy's local `rafiki` volume since 2026-09-18.

    Mounted at /data/photos INSIDE the container -- the same path it had when
    it arrived over NFS. That is deliberate and load-bearing: kopia keys every
    source as <user>@<hostname>:<path>, so keeping /data/photos keeps the
    source identity `root@1da0a4624124:/data/photos` and its entire snapshot
    history. Point it anywhere else and the history is orphaned.

    It nests INSIDE the /data bind below. Docker applies mounts in path-depth
    order, so this one shadows /data/photos from the parent while the other
    eight sources still come from samson over NFS.

    WHY THIS EXISTS: immich moved to the local volume, so samson's
    /export/photos became a stale copy. Without this, kopia would keep
    faithfully backing up the OLD primary -- the same shape as the memos
    incident in docs/data-architecture.md, where everything looked healthy
    because nothing distinguishes "backing up the right data" from "backing up
    data nobody writes to any more".
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

  description = <<-EOT
    LOOKS LIKE A MISTAKE, IS NOT. A container id, kept on purpose.

    kopia keys every source as <user>@<hostname>:<path>. This value is the
    identity the repository already knows -- all 56 sources are
    root@1da0a4624124:/data/... -- so changing it to `mindy` would mint a fresh
    identity and every source would restart from zero history, with the old
    snapshots orphaned under a hostname nothing writes to any more.

    Distinct from the CONTAINER hostname in main.tf, which is `mindy` and
    exists so the id does not change on every recreate.
  EOT
}

variable "repository_username" {
  type    = string
  default = "root"
}

# The document shares, local since 2026-09-18 -- same reasoning as
# var.photos_path. Mounted at /data/<name>, unchanged from when they arrived
# over NFS, so each source keeps its identity and snapshot history.
variable "documents_path" {
  type = string
}

variable "document_shares" {
  type = list(string)
}

# The audio share, local since 2026-09-18 -- same reasoning as var.photos_path.
# Mounted at /data/audio, unchanged from when it arrived over NFS, so the source
# identity `root@1da0a4624124:/data/audio` and its history survive the move.
#
# `audio-archive` deliberately does NOT move: it is archival and stays on
# samson. It reaches this container as an NFS submount under the /data bind,
# which is why that bind's rslave propagation still matters.
variable "audio_path" {
  type = string
}

# --- heartbeat -------------------------------------------------------------

variable "gatus_token" {
  type        = string
  sensitive   = true
  description = "Bearer token for gatus's backups_kopia-mindy external endpoint. From modules/services/gatus."
}

variable "gatus_base_url" {
  type        = string
  description = "e.g. https://status.wvl.app/api/v1/endpoints -- heartbeat.sh appends the endpoint name."
}

variable "heartbeat_max_age_seconds" {
  type    = number
  default = 93600

  description = <<-EOT
    How old the newest snapshot in the repository may be before kopia reports
    down. 26h: the daily 05:00 run plus room for a slow night over the home
    uplink.

    Must stay under the heartbeat interval on the gatus side, or a repository
    that stopped being written to would read as healthy until the heartbeat
    expired -- which is the failure this exists to catch early.
  EOT
}

variable "heartbeat_interval_seconds" {
  type        = number
  default     = 3600
  description = "Seconds between checks. Hourly, so gatus's failure-threshold of 3 means mail within about three hours."
}
