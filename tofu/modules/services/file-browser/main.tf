locals {
  configPath = "/home/filebrowser/config.yaml"
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
      adminUsername = "admin"
      adminPassword = random_password.admin.result

      methods = {
        password = {
          enabled = true
          signup  = false
        }

        oidc = {
          enabled        = true
          issuerUrl      = var.oidc_issuer_url
          clientId       = zitadel_application_oidc.this.client_id
          scopes         = "openid profile email groups"
          userIdentifier = "preferred_username"
          # TODO verify this works
          groupsClaim = "groups"
          adminGroup  = var.oidc_admin_group
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

resource "random_password" "admin" {
  length  = 32
  special = false
}

resource "docker_image" "this" {
  name         = "gtstef/filebrowser:1.5.6-stable-slim"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "filebrowser"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  env = ["FILEBROWSER_CONFIG=${local.configPath}"]

  upload {
    file    = local.configPath
    content = yamlencode(local.config)
  }

  group_add = ["100"]

  ports {
    internal = 80
    external = 8900
  }

  mounts {
    type   = "bind"
    source = "/docker-volumes/filebrowser/config"
    target = "/home/filebrowser/data"
  }

  mounts {
    type   = "bind"
    source = "/docker-volumes/filebrowser/files"
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

  # NOT on mindy's postgres network, and deliberately so since 2026-09-27.
  #
  # It was, inherited verbatim when this container was adopted from compose --
  # the network is still named `db_db-network`, which is compose's
  # <project>_<network>. Nothing ever used it: filebrowser keeps its state in a
  # local BoltDB (FILEBROWSER_DATABASE=.../database.db, baked into the image),
  # there is no database.tf here, no role was created, and no DSN existed in any
  # env or config.
  #
  # Removing it costs nothing and takes the one service whose job is exposing
  # directories to a browser off the network holding memos, kitchenowl and
  # score. Credentials still guarded that; reachability with no purpose did not.

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
