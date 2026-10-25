locals {
  shares = [
    { dir = "gezin-officieel", name = "Gezin officieel", default_enabled = true, source = "/mnt/rafiki/documents/gezin-officieel" },
    { dir = "gezin-officieel-archive", name = "Gezin officieel archive", default_enabled = true, source = "/mnt/rafiki/documents/gezin-officieel-archive" },
    { dir = "audio", name = "Audio", default_enabled = true, source = "/mnt/rafiki/audio" },
    { dir = "audio-archive", name = "Audio archive", default_enabled = true, source = "/mnt/samson/audio-archive" },
    { dir = "wim", name = "Wim privé", default_enabled = false, source = "/mnt/rafiki/documents/wim" },
    { dir = "sara", name = "Sara prive", default_enabled = false, source = "/mnt/rafiki/documents/sara" },
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

      # The default, tmp under the image's home directory, cannot be created:
      # on the remapping daemon the image's files belong to 165536+, which
      # filebrowser's uid 950 under userns_mode = "host" does not own.
      cacheDir = "/home/filebrowser/data/cache"

      # Group-writable and setgid, so what filebrowser creates stays users' and
      # wim's Unison can still write to it. Filebrowser chmods new folders to
      # this mode, so the default, 755, also drops the setgid bit.
      filesystem = {
        createFilePermission      = "664"
        createDirectoryPermission = "2775"
      }

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
          createUser     = true
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
  name         = "gtstef/filebrowser:1.5.8-stable-slim"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "filebrowser"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  userns_mode = "host"

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  env = ["FILEBROWSER_CONFIG=${local.configPath}"]

  upload {
    file    = local.configPath
    content = yamlencode(local.config)
  }

  # 950 is the filebrowser account in nix/hosts/mindy/default.nix; the image's
  # 1000 is wim on mindy. users (100) opens the shares to it. umask 002 keeps
  # the parent folders an upload creates group-writable too.
  user       = "950:950"
  group_add  = ["100"]
  entrypoint = ["/bin/sh", "-c", "umask 002 && exec ./filebrowser"]

  ports {
    internal = 80
    external = var.host_port
  }

  mounts {
    type   = "bind"
    source = "/docker-volumes/filebrowser/config"
    target = "/home/filebrowser/data"
  }

  # Never onto a symlink: Docker follows a symlinked target inside the
  # container and mounts at the link's destination, leaving /files/<dir> a
  # link, and filebrowser then builds paths like
  # /files/audio/mnt/rafiki/audio/... from the resolved name.
  #
  # rslave for audio-archive, an automount: the NFS mount the first access
  # triggers on the host only reaches the container through propagation.
  dynamic "mounts" {
    for_each = { for s in local.shares : s.dir => s }
    content {
      type   = "bind"
      source = mounts.value.source
      target = "/files/${mounts.key}"

      bind_options {
        propagation = "rslave"
      }
    }
  }

  networks_advanced {
    name = docker_network.traefik.name
  }
}

# Shared with traefik and nothing else.
resource "docker_network" "traefik" {
  name       = "traefik-filebrowser"
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false
}
