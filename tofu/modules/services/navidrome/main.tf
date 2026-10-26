locals {
  data_path = "/docker-volumes/navidrome"
}

# ONLY SEEDS IT. Navidrome reads this once, on the first start against an empty
# database, so rotating it here changes nothing; change the password in the UI.
# It also logs the value at that first start.
resource "random_password" "admin" {
  length  = 32
  special = false
}

resource "docker_image" "this" {
  name         = "deluan/navidrome:0.64.2"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "navidrome"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  user = "1000:1000"

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  env = [
    "TZ=Europe/Brussels",
    "ND_PORT=${var.host_port}",
    "ND_CACHEFOLDER=/cache",
    "ND_PLUGINS_FOLDER=${local.plugins_folder}",
    "ND_DEVAUTOCREATEADMINPASSWORD=${random_password.admin.result}",
  ]

  ports {
    internal = var.host_port
    external = var.host_port
    ip       = var.tailscale_ip
  }

  # Remapped, so navidrome reads the library as "other": files need a+r.
  volumes {
    host_path      = "/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300/media/music"
    container_path = "/music"
    read_only      = true
  }

  volumes {
    host_path      = "${local.data_path}/data"
    container_path = "/data"
  }

  volumes {
    host_path      = "${local.data_path}/cache"
    container_path = "/cache"
  }

  dynamic "upload" {
    for_each = data.http.plugin

    content {
      file = "${local.plugins_folder}/${upload.key}.ndp"
      # sensitive only to keep a megabyte of base64 out of every plan.
      content_base64 = sensitive(upload.value.response_body_base64)
    }
  }

  healthcheck {
    test = ["CMD", "curl", "-f", "http://localhost:${var.host_port}/ping"]

    interval     = "1m0s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }
}
