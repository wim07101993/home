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
  hostname = "mindy"

  env = [
    "KOPIA_SERVER_USERNAME=${var.server_username}",
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
    join(" ", [
      "export KOPIA_SERVER_PASSWORD=\"$(cat /run/secrets/user_password | tr -d '\\r\\n')\" &&",
      "export KOPIA_PASSWORD=\"$(cat /run/secrets/repository_password | tr -d '\\r\\n')\" &&",
      # Policies are CODE. ./policies.json is the complete export, and
      # --delete-other-policies makes it authoritative rather than a merge: a
      # policy removed from the file is removed from the repository.
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
      "kopia policy import",
      "--from-file=/app/policies.json",
      "--delete-other-policies",
      "--config-file=/app/repository.config",
      "|| echo 'KOPIA POLICY IMPORT FAILED -- starting with the policies already in the repository' ;",

      "exec kopia server start",
      "--address=0.0.0.0:${var.port}",
      "--tls-cert-file=/app/config/kopia.cert",
      "--tls-key-file=/app/config/kopia.key",

      # NOT /app/config/repository.config. That directory is a read-write bind
      # mount kopia owns, and a bind SHADOWS anything uploaded underneath it --
      # so the generated file has to live outside it. The TLS cert and key stay
      # in the bind, because kopia writes those itself.
      "--config-file=/app/repository.config",
    ]),
  ]

  # 4 GB and a quarter of a core. mindy is a cx43 with 16 GB, and kopia's
  # tree-walk over nine NFS mounts is the workload that produced the
  # `nfs: server not responding` stalls in the 2026-08 incident. The cap is
  # what keeps a backup run from being the reason something else times out.
  memory      = 4096
  memory_swap = 8192
  cpus        = "0.25"

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
          path           = var.sftp_path
          host           = var.sftp_host
          port           = var.sftp_port
          username       = var.sftp_username
          password       = var.sftp_password
          knownHostsData = file("${path.module}/known_hosts")
          externalSSH    = false
          dirShards      = null
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
  mounts {
    type      = "bind"
    source    = "${var.config_path}/data"
    target    = "/data"
    read_only = true

    bind_options {
      propagation = "rslave"
    }
  }

  # The photo library, from mindy's local volume rather than from samson.
  # Nested inside the /data bind above -- see var.photos_path for why the
  # container path must stay /data/photos.
  mounts {
    type      = "bind"
    source    = var.photos_path
    target    = "/data/photos"
    read_only = true
  }

  # Same shape for audio. audio-archive is NOT here -- it stays on samson and
  # arrives as an NFS submount through the /data bind.
  mounts {
    type      = "bind"
    source    = var.audio_path
    target    = "/data/audio"
    read_only = true
  }

  # The document shares, from the local volume. Same nesting and same
  # identity-preserving path as photos above.
  dynamic "mounts" {
    for_each = var.document_shares
    content {
      type      = "bind"
      source    = "${var.documents_path}/${mounts.value}"
      target    = "/data/${mounts.value}"
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

  mounts {
    type      = "bind"
    source    = "${var.config_path}/user_password.txt"
    target    = "/run/secrets/user_password"
    read_only = true
  }

}
