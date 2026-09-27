# Kopia REPOSITORY SERVER, on mindy.
#
# The only machine holding the Hetzner Storage Box credentials and the only one
# that talks to it, which keeps the Storage Box reachable from inside Hetzner
# only. Remote machines (samson) connect here as repository CLIENTS: they
# authenticate with a per-machine server user and never learn the repository
# password.
#
# This is the estate's only off-site backup. It has twice been down for long
# stretches without anyone noticing -- five weeks crash-looping, found by
# reading `docker ps` during an unrelated recovery, and then from 2026-09-14 to
# 2026-09-18 after a clean manual stop that `unless-stopped` correctly never
# undid. Which is why gatus watches it by HEARTBEAT rather than by polling: a
# stopped container and a running-but-failing one look identical from outside,
# and "the container is up" was never the claim worth checking.
#
# Migration runbook: ../../../../samson/kopia/README.md

# The kopia SERVER UI password for var.server_username. Generated per host --
# each instance runs its own UI on its own tailnet address, so there is no
# reason for them to share one.
#
# NOT the repository password (which encrypts the backups and is supplied), and
# not the SFTP password (which reaches the Storage Box and comes from
# modules/hetzner). Three different secrets that have been confused before.
resource "random_password" "server_user" {
  length  = 32
  special = false
}

locals {
  # What kopia backs up: the explicit list when given, otherwise every mount.
  sources = length(var.sources) > 0 ? var.sources : [for k, v in var.mounts : "/data/${k}"]

  # Direct to the Storage Box unless a forwarder is given. mindy is in Hetzner
  # and connects straight there; samson and plop cannot.
  connect_host = var.connect_host == "" ? var.sftp_host : var.connect_host
  connect_port = var.connect_port == 0 ? var.sftp_port : var.connect_port
}

# The server's TLS certificate.
#
# GENERATED, not left to kopia. kopia writes a self-signed pair into
# /app/config on first start only when told to with --tls-generate-cert, which
# then FAILS if the file already exists -- so the flag cannot simply be left
# on. mindy's cert got there that way once, years ago, and existed as
# undeclared host state; samson had none and crash-looped:
#
#   error starting TLS server: open /app/config/kopia.cert: no such file
#
# Self-signed either way. This is a tailnet-only service, and the point of the
# certificate is to encrypt the UI and the repository-server protocol, not to
# prove identity to a CA that has never heard of it.
resource "tls_private_key" "server" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = var.container_hostname
    organization = "wvl.app"
  }

  # The tailnet address is what clients and browsers actually dial, so it has
  # to be a SAN -- a common_name alone has not been accepted since 2017.
  ip_addresses = [var.tailscale_ip]
  dns_names    = [var.container_hostname]

  # 10 years. A self-signed cert nobody validates gains nothing from rotating,
  # and an expiry here would break the UI on a date no one has written down.
  validity_period_hours = 87600

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

resource "docker_image" "this" {
  name         = "kopia/kopia:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "kopia"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  # LOAD-BEARING. Kopia keys every source as <user>@<hostname>:<path>, and
  # without this the container ID becomes the hostname -- so each recreate mints
  # a fresh identity and every source restarts with NO history. The 2026-08
  # audit found 57 of 65 sources holding exactly one snapshot for this reason,
  # and container recreation is more frequent under tofu than under compose,
  # not less.
  hostname = var.container_hostname

  env = [
    "KOPIA_SERVER_USERNAME=${var.server_username}",

    # For heartbeat.sh. Plain env, unlike the two passwords below, because none
    # of these are secret -- and threading them through the entrypoint instead
    # meant a backgrounded prefix-assignment chain that worked only by POSIX
    # subtlety. The token stays in a file.
    "GATUS_BASE=${var.gatus_base_url}",
    "HEARTBEAT_MAX_AGE=${var.heartbeat_max_age_seconds}",
    "HEARTBEAT_INTERVAL=${var.heartbeat_interval_seconds}",
    "HEARTBEAT_ENDPOINT=${var.gatus_endpoint}",
    # NEWLINE-separated, not space. 48 of these paths are film and series
    # titles -- "The Lion King (1994)" -- and a space-separated list would
    # split them into nonsense paths that snapshot nothing. bootstrap-sources.sh
    # sets IFS to match.
    "SOURCES=${join("\n", local.sources)}",
    "PRUNE_SOURCES=${var.prune_sources}",

    # What this instance may prune. Its own sources and nothing else.
    "KOPIA_IDENTITY=${var.repository_username}@${var.repository_hostname}",
  ]

  # The passwords are read from files INSIDE the container and exported, rather
  # than passed as env: env is visible to anything that can run `docker
  # inspect`, and these two unlock the Storage Box and the repository itself.
  #
  # `$` is not escaped here as it is in compose -- that file needed `$$` to stop
  # compose interpolating. This string goes to docker verbatim.
  entrypoint = [
    "/bin/sh",
    "-c",
    join(" ", concat(
      [
        "export KOPIA_SERVER_PASSWORD=\"$(cat /run/secrets/user_password | tr -d '\\r\\n')\" &&",
        "export KOPIA_PASSWORD=\"$(cat /run/secrets/repository_password | tr -d '\\r\\n')\" &&",
      ],

      # Policies are CODE, on exactly one instance. ./policies.json is the
      # complete export and --delete-other-policies makes it authoritative
      # rather than a merge: a policy removed from the file is removed from the
      # repository. Two importers against one repository would therefore delete
      # each other's policies on a schedule -- see var.import_policies.
      #
      # Retention and schedule live inside the repository, not in any config
      # file, so this import is the only way they can be reviewed in a diff.
      # They were invisible until 2026-09-18, and the first look showed photos
      # inheriting keepDaily=1 -- see the module README.
      #
      # NOT gated with && on purpose. A failed import leaves the policies
      # already in the repository and the server still starts: backups running
      # with stale policy beat no backups at all, which is the failure this
      # estate keeps actually having. The failure is loud in `docker logs`.
      var.import_policies ? [
        "kopia policy import",
        "--from-file=/app/policies.json",
        "--delete-other-policies",
        "--config-file=/app/repository.config",
        "|| echo 'KOPIA POLICY IMPORT FAILED -- starting with the policies already in the repository' ;",
        ] : [
        # The `;` is load-bearing: it ends the `export ... &&` chain. Without
        # it the next element is `/app/heartbeat.sh &`, which backgrounds the
        # WHOLE chain -- exports included -- and `exec kopia server start` then
        # runs with no passwords at all.
        "true ;",
      ],

      # The web UI authenticates against users stored IN THE REPOSITORY, not
      # against --server-username/--server-password. Those are basic auth for
      # the repository-server API; the UI ignores them entirely, and kopia says
      # so at startup:
      #
      #   Server will allow connections from users whose accounts are stored
      #   in the repository.
      #
      # With no user, every login fails and the log reads `failed login attempt
      # ... for user wim` -- which looks like a wrong password and is not.
      #
      # `add` THEN `set`, because neither is idempotent on its own: `add` fails
      # if the user exists, and `set` is an update that fails if it does not --
      #
      #   error getting user profile: wim@mindy: user not found
      #
      # Together they create on first run and update the password on every run
      # after, so the UI credential follows random_password.server_user with no
      # manual step.
      #
      # The username is user@host, so each instance owns its own record in the
      # shared repository.
      #
      # NOT gated with &&. A repository that is briefly unreachable should not
      # stop the server from starting; the failure is loud in `docker logs`.
      [
        "kopia server users add ${var.server_username}@${var.container_hostname}",
        "--user-password=\"$KOPIA_SERVER_PASSWORD\"",
        "--config-file=/app/repository.config 2>/dev/null",
        "|| kopia server users set ${var.server_username}@${var.container_hostname}",
        "--user-password=\"$KOPIA_SERVER_PASSWORD\"",
        "--config-file=/app/repository.config",
        "|| echo 'KOPIA USER SET FAILED -- the web UI will reject every login' ;",
      ],

      [
        # Backgrounded before the server takes over the process. It inherits
        # KOPIA_PASSWORD from the exports above, which is the whole reason it
        # lives in here rather than in a checker container of its own. Its
        # non-secret settings come from `env` instead.
        "/app/heartbeat.sh &",

        # Backgrounded too: the first pass reads every byte of every source to
        # hash it, and the server must not wait for that to serve the UI.
        "/app/bootstrap-sources.sh &",

        "exec kopia server start",
        "--address=0.0.0.0:${var.port}",
        "--tls-cert-file=/app/config/kopia.cert",
        "--tls-key-file=/app/config/kopia.key",

        # NOT /app/config/repository.config. That directory is a read-write
        # bind mount kopia owns, and a bind SHADOWS anything uploaded
        # underneath it -- so the generated file has to live outside it. The
        # TLS cert and key stay in the bind, because kopia writes those itself.
        "--config-file=/app/repository.config",
      ],
    )),
  ]

  # 4 GB and a quarter of a core. mindy is a cx43 with 16 GB, and kopia's
  # tree-walk over nine NFS mounts is the workload that produced the
  # `nfs: server not responding` stalls in the 2026-08 incident. The cap is
  # what keeps a backup run from being the reason something else times out.
  memory      = var.memory
  memory_swap = var.memory * 2
  cpus        = var.cpus
  log_opts    = var.log_opts

  # Tailnet only. See var.tailscale_ip for what this looked like before.
  ports {
    internal = var.port
    external = var.port
    ip       = var.tailscale_ip
  }

  # The repository connection, generated rather than hand-maintained.
  #
  # cacheDirectory is ABSOLUTE here. It was "../cache", relative to the config
  # file's own directory -- which resolved to /app/cache only because the file
  # sat in /app/config. Moving the file to /app would have silently pointed the
  # cache at /cache, outside the bind mount, so it would be discarded on every
  # container replacement and rebuilt by re-reading the repository.
  #
  # knownHostsData is SSH HOST PUBLIC keys. Not a secret, and committed as
  # ./known_hosts so a changed Storage Box host key shows up as a diff rather
  # than as a connection that silently starts trusting something else.
  upload {
    file = "/app/repository.config"
    content = jsonencode({
      storage = {
        type = "sftp"
        config = {
          path     = var.sftp_path
          host     = local.connect_host
          port     = local.connect_port
          username = var.sftp_username
          password = var.sftp_password

          # REWRITTEN, not read verbatim. known_hosts entries are keyed by the
          # address you dial -- `[u643732.your-storagebox.de]:23` -- so a client
          # going through the forwarder on bumba presents the Storage Box's own
          # host key from a different address and verification fails.
          #
          # The key material is untouched; only the pattern changes. That keeps
          # the guarantee intact: a forwarder that pointed somewhere else would
          # still be caught, because the key would not match.
          knownHostsData = replace(
            file("${path.module}/known_hosts"),
            "[${var.sftp_host}]:${var.sftp_port}",
            "[${local.connect_host}]:${local.connect_port}",
          )
          externalSSH = false
          dirShards   = null
        }
      }

      caching = {
        cacheDirectory       = "/app/cache"
        maxCacheSize         = 5242880000
        maxMetadataCacheSize = 5242880000
        maxListCacheDuration = 30
      }

      # See var.repository_hostname. These are the client identity and they
      # are not cosmetic.
      hostname = var.repository_hostname
      username = var.repository_username

      description             = "My Repository"
      enableActions           = false
      formatBlobCacheDuration = 900000000000
    })
  }

  # Read by the entrypoint, never passed as env -- `docker inspect` shows env.
  upload {
    file    = "/run/secrets/repository_password"
    content = var.repository_password
  }

  # Written THROUGH the /app/config bind onto the host, which is where kopia
  # expects to read them. Verified 2026-09-23 that an upload under a directory
  # bind lands on the host rather than being shadowed by it.
  upload {
    file    = "/app/config/kopia.cert"
    content = tls_self_signed_cert.server.cert_pem
  }

  upload {
    file    = "/app/config/kopia.key"
    content = tls_private_key.server.private_key_pem
  }

  # Same reasoning: the heartbeat's bearer token is read from a file, not env.
  upload {
    file    = "/run/secrets/gatus_token"
    content = var.gatus_token
  }

  # Creates the first snapshot for any source that has none. See the file --
  # without it a new instance never backs anything up, however correct
  # everything else looks.
  upload {
    file       = "/app/bootstrap-sources.sh"
    content    = file("${path.module}/bootstrap-sources.sh")
    executable = true
  }

  # Reports snapshot freshness to gatus. See the file for why it runs in here
  # rather than as its own container.
  upload {
    file       = "/app/heartbeat.sh"
    content    = file("${path.module}/heartbeat.sh")
    executable = true
  }

  # Retention, scheduling and per-source overrides. See the entrypoint.
  upload {
    file    = "/app/policies.json"
    content = file("${path.module}/policies.json")
  }

  # The nine NFS mounts from samson live UNDER this path, so the bind has to
  # propagate. rslave, not a plain bind: an NFS mount established after the
  # container starts is invisible inside it otherwise, and the container then
  # backs up an empty directory while reporting success. ../immich/main.tf hit
  # the same thing.
  #
  # read_only because a backup reader has no business writing to the source.
  #
  # PHASE 4 of the migration removes this entirely, once samson snapshots its
  # own local disk and connects here as a client -- which is also what deletes
  # the nine NFS mounts from mindy's fstab.
  dynamic "mounts" {
    for_each = var.bind_data_root ? [1] : []
    content {
      type      = "bind"
      source    = "${var.config_path}/data"
      target    = "/data"
      read_only = true

      bind_options {
        propagation = "rslave"
      }
    }
  }

  # Everything this host can see. One bind per entry, nested inside the /data
  # bind above so each shadows whatever the parent carries at that path -- see
  # var.mounts for why the container path is the source's identity.
  #
  # read_only on every one: a backup reader has no business writing to what it
  # is reading.
  dynamic "mounts" {
    for_each = var.mounts
    content {
      type      = "bind"
      source    = mounts.value
      target    = "/data/${mounts.key}"
      read_only = true
    }
  }

  mounts {
    type   = "bind"
    source = "${var.config_path}/kopia-config"
    target = "/app/config"
  }

  mounts {
    type   = "bind"
    source = "${var.config_path}/kopia-cache"
    target = "/app/cache"
  }

  # UPLOADED, not bound from the host. It was
  # ${var.config_path}/user_password.txt -- a file someone had to create by
  # hand, which is fine for one instance and a trap for the second: a missing
  # file is not an error, the container starts, and the server has no password.
  #
  # Generated below, so a new host needs nothing prepared on disk.
  upload {
    file    = "/run/secrets/user_password"
    content = random_password.server_user.result
  }

}
