# Backrest -- restic with a web UI, replacing kopia.
#
# WHY THE MIGRATION. kopia keeps its policies AND its source list inside the
# encrypted repository, so a declarative model needs a reconcile loop in each
# direction: `policy import --delete-other-policies` for policies, and a prune
# pass for sources. The second one never existed, and the gap is not academic --
# /data/media survived its own removal from the config on 2026-09-25, inherited
# the global schedule, and was one scheduled run away from writing 8.4 TB into
# 4.5 TB of free space. Caught by hand. Twice.
#
# Backrest keeps config in ONE JSON FILE and its history in SQLite. So config is
# rendered here and the repository holds no opinions: a path removed from
# var.paths is simply absent from the next snapshot, and the old ones age out
# under var.retention. Nothing is reconciled and no history is deleted to
# express "stop backing this up".
#
# WHAT THIS DELETED: policies.json (1061 lines), bootstrap-sources.sh (100),
# heartbeat.sh (79), prune_sources, KOPIA_IDENTITY, import_policies, the
# self-signed TLS pair, and the `server users add || set` dance.
#
# WHAT IT ADDED: start.sh, two lines, because restic cannot do SFTP passwords.
#
# The UI is HTTP on the tailnet, deliberately. kopia needed a generated
# certificate because it served a repository protocol; this serves a dashboard
# over WireGuard, and providers.tf already makes that argument for postgres.

# The UI password. Generated per host -- each instance runs its own UI on its
# own tailnet address, so there is no reason to share one.
#
# NOT the repository password (which encrypts the snapshots and is supplied) and
# NOT the Storage Box password (which reaches the box and comes from
# modules/hetzner). Three different secrets; kopia had the same three and they
# were confused more than once.
resource "random_password" "ui" {
  length  = 32
  special = false
}

locals {
  # What gets backed up: the explicit list when given, otherwise every mount.
  paths = length(var.paths) > 0 ? var.paths : [for k, v in var.mounts : "/backup/${k}"]

  # Direct to the Storage Box unless a forwarder is given. mindy is in Hetzner
  # and connects straight there; samson cannot.
  connect_host = var.connect_host == "" ? var.sftp_host : var.connect_host
  connect_port = var.connect_port == 0 ? var.sftp_port : var.connect_port

  # The `sync` block, or nothing at all when no identity is supplied.
  #
  # NOTE THE KEY IS `sync`, not `multihost`. The proto field is
  # `Multihost multihost = 7 [json_name="sync"]`, and protojson parses with
  # DiscardUnknown, so spelling it `multihost` would be SILENTLY IGNORED -- the
  # config would look configured and sync would simply never happen.
  sync = var.sync_identity == null ? {} : {
    sync = {
      identity = {
        keyId       = var.sync_identity.keyid
        ed25519priv = var.sync_identity.priv
        ed25519pub  = var.sync_identity.pub
      }

      authorizedClients = [for c in var.sync_authorized_clients : {
        instanceId = c.instance_id
        keyId      = c.keyid
      }]

      knownHosts = [for h in var.sync_known_hosts : {
        instanceId  = h.instance_id
        keyId       = h.keyid
        instanceUrl = h.instance_url
        permissions = [{
          type   = "PERMISSION_READ_OPERATIONS"
          scopes = h.scopes
        }]
      }]
    }
  }

  # Pushed to gatus when a run finishes. See var.gatus_endpoint for why this
  # exists alongside a UI that already shows the same thing.
  #
  # The token is read from a FILE, not interpolated here: config.json is
  # uploaded into the container and `docker inspect` does not show it, but a
  # hook command is echoed into Backrest's own operation log, which the UI
  # displays. A bearer token has no business being in a log line.
  gatus_push = "curl -fsS -m 30 -X POST -H \"Authorization: Bearer $(cat /run/secrets/gatus_token)\" \"${var.gatus_base_url}/${var.gatus_endpoint}/external?success="
}

resource "docker_image" "this" {
  name         = "garethgeorge/backrest:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "backrest"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  # LOAD-BEARING. restic tags every snapshot with the host it was taken on, and
  # without this the container ID becomes the hostname -- so each recreate mints
  # a fresh identity and the UI shows the history starting over. That is the
  # 2026-08 kopia finding (57 of 65 sources holding exactly one snapshot) in a
  # different tool, and container recreation is more frequent under tofu than
  # under compose, not less.
  hostname = var.instance

  # The image's entrypoint is tini -> /docker-entrypoint, which applies the
  # BACKREST_* defaults and then runs whatever `command` says. Overriding
  # `command` rather than `entrypoint` keeps both of those -- an entrypoint
  # override would silently drop BACKREST_DATA and BACKREST_CONFIG and Backrest
  # would come up pointing at $HOME.
  command = ["/app/start.sh"]

  env = [
    # 0.0.0.0 inside the container; the `ports` block below is what actually
    # confines this to the tailnet.
    "BACKREST_PORT=0.0.0.0:${var.port}",

    # The rclone remote restic reaches the repository through, declared by
    # environment so it shows up in a diff. rclone reads
    # RCLONE_CONFIG_<REMOTE>_<KEY> exactly as if it were a config file stanza,
    # which means no rclone.conf and no host state.
    #
    # The PASSWORD is deliberately absent -- start.sh adds it, because it has to
    # be obscured first. See that file.
    "RCLONE_CONFIG_STORAGEBOX_TYPE=sftp",
    "RCLONE_CONFIG_STORAGEBOX_HOST=${local.connect_host}",
    "RCLONE_CONFIG_STORAGEBOX_PORT=${local.connect_port}",
    "RCLONE_CONFIG_STORAGEBOX_USER=${var.sftp_username}",

    # Hetzner's SFTP does not implement the extensions rclone uses to check free
    # space, and without this every operation logs a warning about it.
    "RCLONE_CONFIG_STORAGEBOX_DISABLE_HASHCHECK=true",

    # HOST KEY VALIDATION. Off by default in rclone, which says so on every
    # operation:
    #
    #   NOTICE: No host key validation is being performed. Set known_hosts_file
    #
    # kopia pinned these and dropping the property silently would be the wrong
    # way to migrate. restic encrypts client-side, so the risk is not disclosure
    # -- it is talking to something that is not the Storage Box and believing the
    # repository it serves.
    "RCLONE_CONFIG_STORAGEBOX_KNOWN_HOSTS_FILE=/app/known_hosts",
  ]

  memory      = var.memory
  memory_swap = var.memory * 2
  cpus        = var.cpus
  log_opts    = var.log_opts

  security_opts = ["no-new-privileges:true"]

  # Tailnet only. Without the `ip` this is an unauthenticated-by-default
  # dashboard over every interface the host has.
  ports {
    internal = var.port
    external = var.port
    ip       = var.tailscale_ip
  }

  # THE WHOLE CONFIGURATION. Repos, plans, paths, schedules, retention,
  # integrity checks and the UI credential, in one rendered file.
  #
  # NOT bind-mounted, on purpose. Backrest rewrites this file when someone edits
  # something in the UI, and leaving it only in the container layer is what
  # makes tofu unambiguously authoritative: a UI edit survives until the next
  # apply and no longer. That is the property the whole migration was for, so it
  # is enforced rather than documented.
  #
  # Nothing is lost by not persisting it -- every value here is derived from
  # this module's inputs.
  upload {
    file = "/config/config.json"
    content = jsonencode(merge(local.sync, {
      # Coupled to var.image_tag. See that variable -- wrong in either
      # direction and Backrest either migrates the file out from under this
      # module or refuses to start.
      version  = var.config_version
      instance = var.instance

      # The UI credential, declared. kopia needed `server users add || set` in
      # its entrypoint because its users lived in the repository; here it is a
      # field.
      #
      # base64(bcrypt(password)) -- Backrest base64-decodes before comparing
      # (internal/auth/auth.go), so a bare bcrypt hash fails every login while
      # looking exactly like a wrong password. Which is the kopia UI failure
      # mode, reproduced for a different reason.
      #
      # random_password.bcrypt_hash, NOT tofu's bcrypt() function: bcrypt()
      # generates a fresh salt on every evaluation, so the rendered file would
      # differ on every plan and REPLACE THIS CONTAINER on every apply. The
      # attribute is computed once and stored in state.
      auth = {
        users = [{
          name           = var.ui_username
          passwordBcrypt = base64encode(random_password.ui.bcrypt_hash)
        }]
      }

      repos = [{
        id = "storagebox"

        # rclone:<remote>:<path>. The path is relative to the sub-account's
        # home_directory, which already scopes it to this host.
        uri      = "rclone:storagebox:${var.repo_path}"
        password = var.repository_password

        # Creates the repository on first use. This is also what makes `guid`
        # omittable -- the two are MUTUALLY EXCLUSIVE and setting both fails
        # validation:
        #
        #   auto_initialize set with guid but guid implies that repo is
        #   already initialized
        #
        # It also replaces bootstrap-sources.sh outright. kopia needed 100 lines
        # of shell because a source did not exist until something snapshotted
        # it, so a correctly configured instance could sit backing up nothing --
        # which samson did, silently, on 2026-09-24.
        autoInitialize = true

        # Throttling, declared. kopia's equivalent was a blunt 4 GB memory cap,
        # which limited the damage rather than the contention: the 2026-08
        # `nfs: server not responding` stalls were a backup starving everything
        # else of I/O.
        commandPrefix = {
          ioNice  = "IO_IDLE"
          cpuNice = "CPU_LOW"
        }

        # Reclaims space from snapshots that forget has dropped. Weekly and off
        # the daily path deliberately -- prune rewrites pack files and is the
        # expensive operation.
        prunePolicy = {
          schedule         = { cron = var.prune_cron, clock = "CLOCK_UTC" }
          maxUnusedPercent = 10
        }

        # Verifies the repository can still be read. THIS IS NEW -- kopia never
        # did it here, so "the backups exist" and "the backups are readable"
        # were the same assumption for years. A percentage rather than
        # structureOnly, because a structure check finds a broken index and not
        # a corrupt blob.
        checkPolicy = {
          schedule              = { cron = var.check_cron, clock = "CLOCK_UTC" }
          readDataSubsetPercent = var.check_read_percent
        }
      }]

      # CLOCK_UTC on all three schedules, not CLOCK_LOCAL.
      #
      # The container sets no TZ, so "local" IS UTC and the two are identical
      # today -- the orchestrator says so on startup: `{"timezone": "UTC"}`.
      # That equality is an accident, and the failure it hides is quiet: adding
      # TZ later would shift every schedule two hours in summer, putting the
      # 05:00 backup AFTER the Storage Box snapshot at 07:00 UTC. Each daily
      # snapshot would then contain the previous day's backup, and nothing would
      # report anything wrong -- modules/hetzner/storage-box.tf sizes 14 days of
      # snapshots on the assumption that each holds that day's data.
      plans = [{
        id   = var.instance
        repo = "storagebox"

        # THE LIST. Authoritative in both directions -- see var.paths.
        paths    = local.paths
        excludes = var.excludes

        schedule = { cron = var.backup_cron, clock = "CLOCK_UTC" }

        # ONE retention policy, not fifty. See var.retention.
        retention = {
          policyTimeBucketed = {
            daily   = var.retention.daily
            weekly  = var.retention.weekly
            monthly = var.retention.monthly
          }
        }

        # Skips the snapshot when nothing changed, which matters for documents
        # that go untouched for weeks. Note the gatus hook below treats a skip
        # as SUCCESS -- see there.
        skipIfUnchanged = true

        hooks = [
          # A finished run reports healthy. SKIPPED is included and that is
          # load-bearing: with skipIfUnchanged above, a week of untouched
          # documents produces no snapshot, and omitting it here would let the
          # 26h heartbeat in ../gatus/config.yaml go red on a repository that is
          # perfectly up to date.
          {
            conditions    = ["CONDITION_SNAPSHOT_SUCCESS", "CONDITION_SNAPSHOT_SKIPPED"]
            onError       = "ON_ERROR_IGNORE"
            actionCommand = { command = "${local.gatus_push}true\"" }
          },

          # A failed or partial run reports unhealthy immediately, rather than
          # waiting out the heartbeat. A WARNING counts: restic warns when it
          # could not read a file, and a snapshot missing files is not a
          # successful backup.
          {
            conditions    = ["CONDITION_SNAPSHOT_ERROR", "CONDITION_SNAPSHOT_WARNING"]
            onError       = "ON_ERROR_IGNORE"
            actionCommand = { command = "${local.gatus_push}false\"" }
          },
        ]
      }]
    }))
  }

  # Read by start.sh. A file rather than env, because `docker inspect` shows
  # env and this one can delete the repository.
  upload {
    file    = "/run/secrets/sftp_password"
    content = var.sftp_password
  }

  # Read by the gatus hooks. Same reasoning, plus it keeps the token out of
  # Backrest's operation log -- see local.gatus_push.
  upload {
    file    = "/run/secrets/gatus_token"
    content = var.gatus_token
  }

  upload {
    file       = "/app/start.sh"
    content    = file("${path.module}/start.sh")
    executable = true
  }

  # The Storage Box's SSH HOST public keys. Not a secret, and committed as
  # ./known_hosts so a changed host key shows up as a diff rather than as a
  # connection that silently starts trusting something else.
  #
  # REWRITTEN, not read verbatim. known_hosts entries are keyed by the address
  # you dial -- `[u643732.your-storagebox.de]:23` -- so samson, which goes
  # through bumba's forwarder, is offered the Storage Box's own host key from a
  # different address and validation fails. Only the pattern changes; the key
  # material is untouched, so a forwarder pointing somewhere else is still
  # caught.
  #
  # Its own copy rather than ../kopia/known_hosts: that module is being deleted.
  upload {
    file = "/app/known_hosts"
    content = replace(
      file("${path.module}/known_hosts"),
      "[${var.sftp_host}]:${var.sftp_port}",
      "[${local.connect_host}]:${local.connect_port}",
    )
  }

  # The operation log: every run, its status, bytes moved, and the stderr of
  # whatever failed. This is the only state here worth persisting, and it is
  # still DERIVED -- losing it costs the history view, not a snapshot. Which is
  # why it is a bind and not a declared resource.
  mounts {
    type   = "bind"
    source = "${var.config_path}/data"
    target = "/data"
  }

  # restic's cache. Rebuildable from the repository, but a cold cache makes the
  # next run re-read the index over SFTP, so it is persisted across recreates.
  mounts {
    type   = "bind"
    source = "${var.config_path}/cache"
    target = "/cache"
  }

  # What this host backs up. One bind per entry, all read-only -- a backup
  # reader has no business writing to its sources.
  #
  # /backup, not /data: /data is Backrest's own. See var.mounts.
  #
  # No parent bind and no rslave propagation, unlike kopia. Nothing arrives as
  # an NFS submount after start any more -- each host backs up its own local
  # disk, which is what the 2026-09-24 split was for.
  dynamic "mounts" {
    for_each = var.mounts
    content {
      type      = "bind"
      source    = mounts.value
      target    = "/backup/${mounts.key}"
      read_only = true
    }
  }
}
