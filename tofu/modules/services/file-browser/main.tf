locals {
  shares = [
    { dir = "gezin-officieel", name = "Gezin officieel", default_enabled = true, bind = true },
    { dir = "gezin-officieel-archive", name = "Gezin officieel archive", default_enabled = true, bind = true },
    { dir = "audio", name = "Audio", default_enabled = true, bind = true },
    { dir = "audio-archive", name = "Audio archive", default_enabled = true, bind = false },
    { dir = "wim", name = "Wim privé", default_enabled = false, bind = true },
    { dir = "sara", name = "Sara prive", default_enabled = false, bind = true },
  ]

  configPath = "/home/filebrowser/config.yaml"
  config = {
    server = {
      port = 80

      # EXPLICIT because the config file moved. The database path defaults
      # relative to the config, so leaving it out risks filebrowser creating a
      # fresh, empty database next to the new config location and silently
      # abandoning the real one -- users, shares and all.
      database = "/home/filebrowser/data/database.db"

      sources = [for s in local.shares : {
        path = "/files/${s.dir}"
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
    external = var.host_port
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

  # Each is a SYMLINK on the host under /docker-volumes/filebrowser/files,
  # pointing at the real directory on rafiki. Docker resolves it host-side.
  dynamic "mounts" {
    for_each = { for s in local.shares : s.dir => s if s.bind }
    content {
      type   = "bind"
      source = "/docker-volumes/filebrowser/files/${mounts.key}"
      target = "/files/${mounts.key}"
    }
  }

  networks_advanced {
    name = var.traefik_network
  }
}
