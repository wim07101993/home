resource "random_password" "ui" {
  length  = 32
  special = false
}

locals {
  paths = distinct(flatten(var.backup[*].paths))

  repositories = concat([local.storage_box_repository], local.rest_server_repositories)

  repo_settings = {
    commandPrefix = {
      # CPU only after normal processes
      ioNice = "IO_IDLE"
      # disk reads go in the "idle" class: served only when nobody else is using the disk
      cpuNice = "CPU_LOW"
    }

    prunePolicy = {
      schedule         = { cron = "0 4 * * 0", clock = "CLOCK_UTC" }
      maxUnusedPercent = 10
    }

    checkPolicy = {
      schedule              = { cron = "0 3 1 * *", clock = "CLOCK_UTC" }
      readDataSubsetPercent = 2
    }

    autoInitialize = true
  }
}

resource "docker_image" "this" {
  name         = "garethgeorge/backrest:v1.14.1"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "backrest"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  hostname = var.instance

  userns_mode = "host"

  command = ["/app/start.sh"]

  env = concat(
    ["BACKREST_PORT=0.0.0.0:${var.port}"],
    # The Storage Box's rclone remote: see storage-box.tf.
    local.storage_box_env,
  )

  memory      = 2048
  memory_swap = 2048 * 2
  cpus        = 0.5

  # DAC_OVERRIDE: with userns_mode = "host" the image's files belong to 165536,
  # not root, and root has to run start.sh. It also reads every source. A
  # restore that should keep file owners needs more, such as CAP_CHOWN and
  # CAP_FOWNER.
  capabilities {
    drop = ["ALL"]
    add  = ["CAP_DAC_OVERRIDE"]
  }
  security_opts = ["no-new-privileges:true"]

  # Tailnet only. Without the `ip` this is an unauthenticated-by-default
  # dashboard over every interface the host has.
  ports {
    internal = var.port
    external = var.port
    ip       = var.tailscale_ip
  }

  upload {
    file = "/config/config.json"
    content = jsonencode({
      version  = 6
      instance = var.instance

      auth = {
        users = [{
          name           = "wim"
          passwordBcrypt = base64encode(random_password.ui.bcrypt_hash)
        }]
      }

      repos = [for r in local.repositories : r.repo]

      plans = [for r in local.repositories : {
        id   = r.plan
        repo = r.repo.id

        paths = local.paths

        schedule = { cron = "0 5 * * *", clock = "CLOCK_UTC" }

        retention = {
          policyTimeBucketed = {
            daily   = 7
            weekly  = 4
            monthly = 6
          }
        }

        skipIfUnchanged = true
      }]
    })
  }

  upload {
    file    = "/run/secrets/sftp_password"
    content = random_password.sftp.result
  }

  upload {
    file       = "/app/start.sh"
    content    = file("${path.module}/start.sh")
    executable = true
  }

  upload {
    file    = "/app/known_hosts"
    content = local.storage_box_known_hosts
  }

  mounts {
    type   = "bind"
    source = "${var.config_path}/data"
    target = "/data"
  }

  mounts {
    type   = "bind"
    source = "${var.config_path}/cache"
    target = "/cache"
  }

  dynamic "mounts" {
    for_each = toset(local.paths)
    content {
      type      = "bind"
      source    = mounts.value
      target    = mounts.value
      read_only = true
    }
  }
}
