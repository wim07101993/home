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

variable "mounts" {
  type = map(string)

  description = <<-EOT
    What this container can SEE, as <path under /data> => <host path>. These
    are bind mounts, not kopia sources -- what actually gets backed up is
    var.sources below, which usually mirrors this and sometimes does not.

    THE KEY IS LOAD-BEARING. kopia identifies every source as
    <user>@<hostname>:<path>, so the container path IS the source's identity
    and its entire snapshot history. mindy's photos are keyed
    `photos` because they were `/data/photos` when they arrived over NFS from
    samson; pointing them at /data/photo-library instead would orphan years of
    snapshots and silently start over.

    So these keys are chosen to match history, not to be tidy.

    Each entry nests INSIDE var.data_path below where that is set. Docker
    applies mounts in path-depth order, so a local entry shadows whatever the
    parent bind carries at the same path -- which is how photos and audio moved
    from samson's NFS to mindy's local volume without changing identity.

    WHY THAT MATTERS: immich moved to the local volume and samson's
    /export/photos became a stale copy. Without the shadowing entry, kopia
    would have kept faithfully backing up the OLD primary -- the same shape as
    the memos incident in docs/data-architecture.md, where everything looked
    healthy because nothing distinguishes "backing up the right data" from
    "backing up data nobody writes to any more".
  EOT
}

variable "config_path" {
  type    = string
  default = "/docker-volumes/kopia"

  description = <<-EOT
    Where this instance keeps its own state on the host. THREE directories must
    exist beneath it before the first apply:

      <config_path>/kopia-config   TLS cert/key and kopia's own config
      <config_path>/kopia-cache    content and metadata cache, up to 10 GB
      <config_path>/data           the root the sources nest inside

    They are `mounts`, not `volumes`, and docker does NOT create the source of
    a bind mount -- it refuses to start the container:

      invalid mount config for type "bind": bind source path does not exist

    Which is the good failure. The same paths as `volumes` would be created
    silently and empty, and kopia would come up with no config and no cache and
    report itself healthy.
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
  type        = string
  description = "The shared sub-account login. No default: it is computed by Hetzner and comes from modules/hetzner, so the account number is not written down twice."
}

variable "connect_host" {
  type    = string
  default = ""

  description = <<-EOT
    Where this kopia CONNECTS, when that differs from the Storage Box itself.
    Empty means connect to var.sftp_host directly, which is what mindy does.

    samson and plop cannot authenticate to the Storage Box at all -- it offers
    them no auth methods, see ../storage-box-proxy -- so they point here at
    bumba's forwarder instead. The repository, the path and the credentials are
    identical; only the address changes.
  EOT
}

variable "connect_port" {
  type        = number
  default     = 0
  description = "Port for var.connect_host. 0 means use var.sftp_port."
}

variable "sftp_host" {
  type        = string
  description = "The Storage Box's own FQDN, from modules/hetzner. Still needed when connect_host is set: it is the pattern the known_hosts rewrite matches on."
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

variable "gatus_endpoint" {
  type        = string
  description = "This instance's gatus external endpoint, e.g. backups_kopia-mindy. Must exist in ../gatus/config.yaml; a name that does not is a 404 on every push and an endpoint permanently down."
}

variable "import_policies" {
  type    = bool
  default = false

  description = <<-EOT
    Whether this instance imports ./policies.json into the repository.

    EXACTLY ONE instance may do this, and mindy is it. The import runs with
    `--delete-other-policies`, which makes the file authoritative for the WHOLE
    repository -- so a second importer would delete every policy belonging to
    the first, on a schedule, silently.

    That also means policies.json must carry the policies for every host's
    sources, not just mindy's. A source whose policy is missing falls back to
    the global defaults rather than erroring.

    Defaults to false so a new instance cannot quietly become a second writer.
  EOT
}

variable "container_hostname" {
  type = string

  description = <<-EOT
    The DOCKER container hostname. Distinct from var.repository_hostname, which
    is kopia's identity in the repository -- they were the same string on mindy
    and that made the difference invisible.

    Set it per host. Left hardcoded it produces a container on samson that
    calls itself mindy, which costs nothing until someone is reading logs at
    2am.
  EOT
}

variable "memory" {
  type        = number
  default     = 4096
  description = "Container memory in MB. memory_swap is set to twice this -- docker's default, stated explicitly because omitting it never settles."
}

variable "cpus" {
  type    = string
  default = "0.25"

  description = <<-EOT
    A quarter core suits mindy, whose kopia reads over NFS and whose tree-walk
    produced the `nfs: server not responding` stalls in the 2026-08 incident --
    the cap is what stops a backup being the reason something else times out.

    A host that hashes its OWN disk wants more: samson reads ~800 GB locally on
    its first run, and at 0.25 that is bounded by CPU rather than by the array.
  EOT
}

variable "bind_data_root" {
  type    = bool
  default = true

  description = <<-EOT
    Whether to bind <config_path>/data at /data as the root the sources nest
    inside.

    TRUE on mindy, and load-bearing there: samson's shares arrive as NFS
    mounts UNDER that host path, after the container has started, and only a
    bind with rslave propagation makes them visible inside. Without it kopia
    backs up empty directories and reports success.

    FALSE where the sources are local. samson has no submounts to propagate,
    and the bind actively breaks it: the bind is read-only, so docker cannot
    create the nested mount targets /data/media and friends inside it --

      Unable to upload volume content: mkdirat data/audio-archive:
      read-only file system

    It works on mindy only because those directories already exist on the host
    as NFS mountpoints. The alternative is to mkdir them on every new host,
    which is host state for no benefit.
  EOT
}

variable "log_opts" {
  type    = map(string)
  default = {}

  description = <<-EOT
    json-file logging options, which must MATCH WHAT THE DAEMON ALREADY DOES.

    Empty everywhere as of 2026-09-28, and that is the whole point: no host's
    /etc/docker/daemon.json sets log-opts any more, so every container comes up
    with an empty LogConfig and an omitted value here matches it.

    IT IS NOT A FREE CHOICE. `log_opts` is Optional and ForceNew but NOT
    Computed, so omitting it asserts "this must be empty" rather than "whatever
    the daemon says". If a daemon ever stamps values again, every container on
    that host must restate them here or the provider reads the live values back,
    sees none configured, and REPLACES the container -- on every plan, forever,
    because the replacement gets stamped again. samson ran that way until its
    daemon.json was cleaned up.
  EOT
}

variable "sources" {
  type    = list(string)
  default = []

  description = <<-EOT
    What kopia BACKS UP -- container paths, each becoming a kopia source with
    its own policy and history. EMPTY means "every mount in var.mounts", which
    is the common case and why most instances never set this.

    Set it when what you MOUNT and what you BACK UP differ. samson mounts the
    whole 8.4 TB media library at /data/media but snapshots only 48 chosen
    paths beneath it -- the library does not fit in the Storage Box, and the
    selection is a deliberate decision about what is worth off-site rather than
    a consequence of how the directories happen to be arranged.

    Every path listed here must exist inside a mount from var.mounts.
  EOT
}

variable "prune_sources" {
  type    = bool
  default = false

  description = <<-EOT
    Delete kopia sources belonging to this instance that var.sources no longer
    declares -- and their snapshots with them.

    This is what makes the model actually declarative. Without it, adding a
    path creates a source and removing one leaves it in the repository
    forever, still on the global schedule. The counterpart to
    `--delete-other-policies`, which policies already have.

    IT DELETES BACKUPS. Scoped to this instance's own <user>@<host>, so no host
    can prune another's, and off by default so a new instance cannot prune
    before anyone has seen what it would remove.

    Turn it on once the source list is settled. During a migration -- where a
    path is deliberately live on two hosts at once -- leave it off.
  EOT
}
