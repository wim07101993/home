# renovate: datasource=docker depName=garethgeorge/backrest
#
# THE `v` IS PART OF THE TAG. "1.14.1" does not exist and fails at apply time
# with `manifest unknown`, the same way the plex tag did on 2026-09-19.
#
# The BARE tag is the ALPINE build (goreleaser's `alpine` docker id publishes
# both `{{ .Tag }}` and `{{ .Tag }}-alpine`), and that is load-bearing: this
# module needs rclone for the repository transport, curl for the gatus hooks and
# sh for start.sh. The `-scratch` variant has none of them and would fail at
# runtime rather than at plan time.
variable "image_tag" {
  type    = string
  default = "v1.14.1"
}

variable "config_version" {
  type    = number
  default = 6

  description = <<-EOT
    The config.json schema version, which is COUPLED TO var.image_tag and must
    not be bumped independently.

    Backrest computes its own CurrentVersion as the LENGTH OF ITS MIGRATION
    LIST (internal/config/migrations). v1.14.1 ships six, so this is 6. The
    coupling runs both ways and both directions fail:

      too LOW    Backrest runs migrations on the file, rewrites it, and the
                 running config stops matching what this module rendered
      too HIGH   it refuses to start --

                   config version 7 is greater than the latest known config
                   format 6

    Version 0 is also rejected for a non-empty config, so this cannot simply be
    omitted:

      config version 0 is invalid

    When bumping var.image_tag, count the migration list at that tag.
  EOT
}

variable "instance" {
  type = string

  description = <<-EOT
    THE IDENTITY. Backrest's instance name, and also the container hostname --
    restic tags every snapshot with the host it was taken on.

    Set it per host and then leave it alone. Changing it makes this instance
    stop recognising its own snapshot history, which is the kopia lesson from
    the 2026-08 audit repeated in a different tool: 57 of 65 sources held
    exactly one snapshot because the identity moved under them.

    Unlike kopia, this is one value rather than three (container hostname,
    repository hostname, repository username). That was never a feature.
  EOT
}

variable "tailscale_ip" {
  type        = string
  description = "The host's tailnet address. The UI binds to THIS, not 0.0.0.0 -- see main.tf. There is no TLS here and none is needed: the transport is a WireGuard tunnel, the same reasoning providers.tf uses for postgres."
}

variable "port" {
  type = number
}



variable "excludes" {
  type    = list(string)
  default = []

  description = "Glob patterns excluded from every path in var.paths. Case-sensitive; Backrest has a separate iexcludes for the other kind."
}

variable "config_path" {
  type    = string
  default = "/docker-volumes/backrest"

  description = <<-EOT
    Where this instance keeps its own state on the host. TWO directories must
    exist beneath it before the first apply:

      <config_path>/data     the SQLite operation log -- history and progress
      <config_path>/cache    restic's cache, which makes the second run fast

    There is deliberately no `config` directory. config.json is uploaded into
    the container layer rather than bind-mounted, so a UI edit cannot outlive
    the next apply -- see the upload block in main.tf.

    They are `mounts`, not `volumes`, and docker does NOT create the source of
    a bind mount -- it refuses to start the container:

      invalid mount config for type "bind": bind source path does not exist

    Which is the good failure. The same paths as `volumes` would be created
    silently and empty.

    Neither holds anything that is not reproducible, and losing `data` costs
    the HISTORY VIEW, not a single backup -- the snapshots live in the
    repository on the Storage Box. That is the test for whether state belongs
    in code: nothing here does, so nothing here is declared.
  EOT
}

# --- the repository ---------------------------------------------------------

variable "repository_password" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Encrypts the restic repository. NOT the Storage Box credential below, and
    NOT the kopia repository password -- a third distinct secret, and the three
    have been confused before.

    Written into config.json, which Backrest requires in cleartext. Losing it
    makes every snapshot unreadable.

    GENERATED in the root -- random_password.backrest_repository -- and shared
    by both instances. It can be generated because it configures nothing at
    plan time; see the comment there for why that distinction matters and why
    the resource carries prevent_destroy.
  EOT
}

variable "repo_path" {
  type        = string
  default     = "restic"
  description = "Path of the repository RELATIVE TO the sub-account's home_directory, which already scopes it to this host (backrest/<host>/). So the repository lands at backrest/<host>/restic."
}

variable "storage_box_id" {
  type        = number
  description = "The Storage Box this instance's sub-account is created on. From modules/hetzner -- the box is estate-level, the sub-account in ./storage-box.tf is not."
}

variable "sftp_host" {
  type        = string
  description = "The Storage Box's own FQDN. No default: it comes from modules/hetzner as a computed attribute, so the account number is not written down twice."
}

variable "sftp_port" {
  type        = number
  default     = 23
  description = "Hetzner's extended SSH service."
}

variable "connect_host" {
  type    = string
  default = ""

  description = <<-EOT
    Where this instance CONNECTS, when that differs from the Storage Box
    itself. Empty means connect directly, which is what mindy does from inside
    Hetzner.

    samson cannot authenticate to the box at all -- it is offered no auth
    methods, see ../storage-box-proxy -- so it points at bumba's forwarder
    instead. Credentials and path are identical; only the address changes.

    Unlike kopia, there is no known_hosts rewriting to do here: rclone is
    pointed at the forwarder and verifies nothing, because the payload is
    already encrypted client-side by restic and the hop is inside the tailnet.
  EOT
}

variable "connect_port" {
  type        = number
  default     = 0
  description = "Port for var.connect_host. 0 means use var.sftp_port."
}

# --- schedules and retention ------------------------------------------------

variable "backup_cron" {
  type        = string
  default     = "0 5 * * *"
  description = "When the backup runs. 05:00 keeps the existing kopia window, which the Storage Box snapshot_plan at 07:00 UTC is sized around."
}

variable "retention" {
  type = object({
    daily   = number
    weekly  = number
    monthly = number
  })
  default = {
    daily   = 7
    weekly  = 4
    monthly = 6
  }

  description = <<-EOT
    Snapshot retention, applied by restic forget.

    ONE POLICY FOR THE WHOLE PLAN, and that is the correction. kopia's
    equivalent was 1061 lines of policies.json holding one meaningful entry and
    fifty pins that existed only to stop sources nobody wanted -- because there
    the policy was the only place a source could be disabled.

    A path that should not be backed up comes out of var.paths instead.
  EOT
}

variable "prune_cron" {
  type        = string
  default     = "0 4 * * 0"
  description = "When restic prune reclaims space from forgotten snapshots. Weekly, and deliberately not on the daily path -- prune rewrites pack files and is the expensive one."
}

variable "check_cron" {
  type        = string
  default     = "0 3 1 * *"
  description = "When restic check verifies repository integrity. Monthly. This is the thing kopia never did here: it reads structure and a sample of pack data, so a repository that has silently rotted says so before a restore needs it."
}

variable "check_read_percent" {
  type        = number
  default     = 2
  description = "Percentage of pack data check actually reads. Structure-only checking finds a broken index; it does not find a corrupt blob. 2% a month over a 900 GB repository is ~18 GB read and covers the repository in about four years -- the point is a continuous sample, not a full verify."
}

# --- observability ----------------------------------------------------------

variable "gatus_token" {
  type        = string
  sensitive   = true
  description = "Bearer token for this instance's gatus external endpoint. From modules/services/gatus."
}

variable "gatus_base_url" {
  type        = string
  description = "e.g. https://status.wvl.app/api/v1/endpoints -- the hook appends the endpoint name."
}

variable "gatus_endpoint" {
  type        = string
  description = <<-EOT
    This instance's gatus external endpoint, e.g. backups_backrest-mindy. Must
    exist in ../gatus/config.yaml; a name that does not is a 404 on every push
    and an endpoint permanently down.

    Backrest's UI shows what happened when someone looks at it. This is what
    reports when nobody is looking, and it is the half that caught neither of
    kopia's two outages -- because it did not exist yet.
  EOT
}

# --- UI ---------------------------------------------------------------------

variable "ui_username" {
  type    = string
  default = "wim"
}

# --- resources --------------------------------------------------------------

variable "memory" {
  type        = number
  default     = 2048
  description = "Container memory in MB. memory_swap is set to twice this -- docker's default, stated explicitly because omitting it never settles. Lower than kopia's 4096: restic's index is smaller than kopia's cache budget, and ioNice/cpuNice below do the throttling kopia did with a hard cap."
}

variable "cpus" {
  type    = string
  default = "0.5"

  description = <<-EOT
    Note the format trap: "0.5" and "4.0", never "4". docker normalises it, and
    `cpus = "4"` reads back as a change that FORCES REPLACEMENT -- rebuilding
    the container on every apply. Cost samson and plop an afternoon.
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

# --- multihost sync ---------------------------------------------------------

variable "sync_identity" {
  type = object({
    keyid = string
    priv  = string
    pub   = string
  })
  default   = null
  sensitive = true

  description = <<-EOT
    This instance's ed25519 sync identity. null disables sync entirely, which is
    the default and what both hosts ran with until 2026-09-27.

    SUPPLIED, and it has to be. Backrest generates an identity itself when this
    is absent -- PopulateRequiredFields in internal/config/config.go -- and then
    WRITES IT BACK into config.json. Since this module keeps config.json in the
    container layer rather than a bind mount, that generated identity is
    discarded on every container replacement and a fresh one minted on the next
    start. A peer that declared the old keyid would break on every apply.

    Pinning it here means `mutated` stays false, Backrest never rewrites the
    file, and the keyids are stable. config.json stays entirely tofu-owned.

    Generate a pair with ./backrest-identity.sh (in tofu/), which writes
    straight into secrets.auto.tfvars. The fields map to v1.PrivateKey:

      keyid -> keyId         "ed25519." + base64url(sha256(raw pubkey))
      priv  -> ed25519priv   base64 of the raw 32-byte SEED, unpadded
      pub   -> ed25519pub    base64 of the raw 32-byte public key, unpadded

    A mismatched pair fails loudly rather than silently -- NewPrivateKey derives
    the public key from the seed and rejects the config if it disagrees.
  EOT
}

variable "sync_authorized_clients" {
  type = list(object({
    instance_id = string
    keyid       = string
  }))
  default = []

  description = <<-EOT
    Peers allowed to connect to THIS instance and push their operations here.
    Set on the host you actually open -- mindy.

    NO PERMISSIONS FIELD, deliberately. The grant that matters lives on the
    CLIENT's known-host entry, not here: PERMISSION_READ_OPERATIONS on an
    authorizedClient is documented as having no effect, because the host never
    pushes operations down. Backrest's own sync test declares these as
    `{Keyid, InstanceId}` and nothing more.
  EOT
}

variable "sync_known_hosts" {
  type = list(object({
    instance_id  = string
    keyid        = string
    instance_url = string
    scopes       = list(string)
  }))
  default = []

  description = <<-EOT
    Hosts THIS instance pushes its operations up to. Set on the client --
    samson.

    scopes limits what is pushed: "*" for everything, or "repo:<id>" /
    "plan:<id>". The permission is granted here because this is the side doing
    the pushing -- see var.sync_authorized_clients.

    instance_url is plain http over the tailnet. The handshake is signed with
    the ed25519 identities above, so the transport is not what authenticates
    it, and providers.tf makes the same argument for postgres.

    NOTE: nothing is pushed while the host is down, so this is a convenience
    layer over the dashboards and NOT a monitoring path. gatus stays the thing
    that reports when nobody is looking, and it has no dependency between the
    two hosts.
  EOT
}

variable "backup" {
  type = list(object({
    mounts = map(string)
    paths  = optional(list(string), [])
  }))

  description = <<-EOT
    What to back up, contributed by the services that own the data -- the same
    shape as var.routing on the reverse proxy. Each entry is one service's
    `backup` output.

    mounts: <name under /backup> => <host path>. THE KEY IS THE SNAPSHOT
    IDENTITY: restic records the path, so renaming a key starts that path's
    history over rather than moving it.

    paths: optional. Empty means "every mount in this entry". Set it where what
    is MOUNTED and what is BACKED UP differ -- plex mounts the whole media
    library and backs up a chosen subset, because the library does not fit in
    the Storage Box.
  EOT
}
