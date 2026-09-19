# drive.wvl.app -- file-browser, on mindy.
#
# Serves six shares: `audio` and `audio-archive` still over NFS from samson, and
# the four document shares now local on rafiki (see var.document_shares). The
# 2 GB upload limit comes from the `drive-size-limit` middleware in the
# reverse-proxy module's mindy/dynamic.yml.

# CONFIG.YAML LIVES HERE NOW, not on the host.
#
# It used to be a hand-edited file at <config_path>/config.yaml, last touched in
# May and listing all six sources by hand -- a second place to remember whenever
# a share was added. It is generated below and uploaded into the container.
#
# It is uploaded to /home/filebrowser/config.yaml, NOT into <config_path>. That
# directory is a bind mount, and a bind mount SHADOWS an upload to the same path:
# the file would be written into the image layer and then hidden by the mount,
# leaving filebrowser reading the stale host copy with no error anywhere.
#
# WHAT REACHES EXISTING USERS AND WHAT DOES NOT -- the two are not the same, and
# the difference is not documented upstream. Both were read off v1.5.6 source:
#
#   scopes       ARE re-applied on every startup. cmd/user.go validateUserInfo
#                -> updateUserScopes adds a scope for any default_enabled source
#                the user lacks. Flipping default_enabled to true takes effect
#                on the next container start, for everyone.
#
#   permissions  are NOT. updatePermissions returns early on `user.Version >= 1`
#                -- it is a one-time migration off a deprecated field, not a
#                sync. Existing users keep whatever they have; user_permissions
#                reaches new accounts only.
#
#   admin login  IS re-applied every startup. cmd/user.go resets the password of
#                auth.adminUsername to auth.adminPassword whenever the latter is
#                non-empty. Which is why the credential below is generated here
#                rather than kept by hand.
#
# See README.md.
locals {
  config = {
    server = {
      port = 80

      # EXPLICIT because the config file moved. The database path defaults
      # relative to the config, so leaving it out risks filebrowser creating a
      # fresh, empty database next to the new config location and silently
      # abandoning the real one -- users, shares and all.
      database = "/home/filebrowser/data/database.db"

      sources = [for s in var.sources : {
        path = s.path
        name = s.name
        config = {
          defaultEnabled   = s.default_enabled
          defaultUserScope = "/"
        }
      }]
    }

    auth = {
      # SIBLINGS OF `methods`, not members of it. They sit on Auth alongside
      # Methods in the v1.5.6 struct, and nesting them one level deeper is not
      # ignored -- the YAML loader is strict and the container refuses to start:
      #
      #   [FATAL] error unmarshaling YAML data: [3:5] unknown field "adminPassword"
      #
      # RESET ON EVERY STARTUP, by design. cmd/user.go rewrites this user's
      # password from the config whenever adminPassword is non-empty, so a
      # password changed in the UI does not survive a restart. That is the
      # point: the credential is owned here, and `tofu output -raw
      # filebrowser_admin_password` is how it is read back.
      adminUsername = "admin"
      adminPassword = random_password.admin.result

      methods = {
        password = {
          enabled = true

          # WAS TRUE. Signup is an open account-creation form on a
          # public-facing host, and it became materially worse the moment any
          # source got default_enabled: a self-registered stranger would be
          # created with scopes for the family shares. Upstream's own comment
          # on this field reads "not secure".
          signup = false
        }

        oidc = {
          enabled        = true
          issuerUrl      = var.oidc_issuer_url
          clientId       = var.oidc_client_id
          scopes         = "openid profile email groups"
          userIdentifier = "preferred_username"
          groupsClaim    = "groups"
          adminGroup     = var.oidc_admin_group

          # userGroups is deliberately unset. It restricts login to the listed
          # groups and blocks everyone else -- including every current user, if
          # zitadel does not actually emit a `groups` claim. It does not today:
          # `wim` is not admin despite adminGroup being configured, which is the
          # same claim going unmatched. Verify the claim before setting this.
        }
      }
    }

    userDefaults = {
      account = {
        permissions = var.user_permissions
      }
    }
  }
}

# Never typed by a human, so there is no reason for it to be short or memorable.
# `special` is off to keep it safe to paste into a shell or a URL-encoded form.
resource "random_password" "admin" {
  length  = 32
  special = false
}

resource "docker_image" "this" {
  name         = "gtstef/filebrowser:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "filebrowser"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  env = ["FILEBROWSER_CONFIG=/home/filebrowser/config.yaml"]

  upload {
    file    = "/home/filebrowser/config.yaml"
    content = yamlencode(local.config)
  }

  # GROUP 100 IS WHAT MAKES THE LOCAL SHARES READABLE, and it only became
  # necessary when they stopped being NFS.
  #
  # Every share is root:100 mode 2770 -- no access for "other". The image runs
  # as uid 1000, whose only group inside the container is 1000. Over NFS that
  # worked anyway: the client sends the uid and samson answers the ACCESS call
  # using the groups it resolves for uid 1000 server-side, which include 100.
  # On a local filesystem the kernel uses the container's own /etc/group, gets
  # only group 1000, and denies -- same uid, same mode, different answer.
  #
  # Proof, if this is ever doubted: /files/audio-archive is root:100 2770 and
  # still NFS. It reads fine while /files/sara, identical in every way except
  # the filesystem, returns EACCES.
  #
  # The setgid bit on those directories keeps new uploads in group 100, so this
  # stays sufficient as content is added.
  group_add = ["100"]

  ports {
    internal = 80
    external = var.host_port
  }

  mounts {
    type   = "bind"
    source = var.config_path
    target = "/home/filebrowser/data"
  }

  # THE rslave PROPAGATION IS LOAD-BEARING, and its absence does not error.
  #
  # var.files_path still holds the `audio` and `audio-archive` NFS mounts from
  # samson. They are plain `_netdev` entries in mindy's /etc/fstab, so they are
  # established during boot with no ordering guarantee against docker starting
  # this container. Lose the race under docker's default (private) propagation
  # and the container keeps the empty pre-mount view forever, serving empty
  # directories cheerfully, with no error anywhere.
  #
  # (An earlier version of this comment claimed these were x-systemd.automount
  # and therefore mounted lazily on first access. They are not -- fstab has no
  # automount entries at all. The conclusion holds; the stated reason did not.)
  #
  # The four document shares below are mounted directly and need no propagation:
  # they are on rafiki, with nothing mounted underneath them.
  #
  # `mounts` rather than `volumes` purely because `volumes` has no propagation
  # option.
  mounts {
    type   = "bind"
    source = var.files_path
    target = "/files"

    bind_options {
      propagation = "rslave"
    }
  }

  # Audio, from rafiki. `audio-archive` is deliberately absent -- it is archival,
  # stays on samson, and still arrives over NFS through the parent bind.
  mounts {
    type   = "bind"
    source = var.audio_path
    target = "/files/audio"
  }

  # The document shares, from the local volume rather than from samson.
  # See var.documents_path. `audio`, `audio-archive`, `media` and `backups`
  # still arrive over NFS through the parent bind above -- audio is 55.4 GB and
  # does not fit on rafiki yet.
  dynamic "mounts" {
    for_each = var.document_shares
    content {
      type   = "bind"
      source = "${var.documents_path}/${mounts.value}"
      target = "/files/${mounts.value}"
    }
  }

  networks_advanced {
    name = var.traefik_network
  }

  # mindy's postgres.
  networks_advanced {
    name = var.db_network
  }

  # A share can be mounted and still be invisible: filebrowser only serves paths
  # that appear in server.sources. Mounting one without adding it to var.sources
  # produces no error at any layer -- the directory is simply not there in the
  # UI. Catch it at plan time instead.
  lifecycle {
    precondition {
      condition = length(setsubtract(
        toset([for s in var.document_shares : "/files/${s}"]),
        toset([for s in var.sources : s.path]),
      )) == 0
      error_message = "Every document share must have a matching entry in var.sources, or it will be mounted but unreachable."
    }
  }

  # Compose also made `filebrowser_filebrowser-network` -- one container, no
  # peers. Not reproduced; left orphaned by the cutover and removable.
}
