resource "docker_image" "this" {
  name         = "binwiederhier/ntfy:v2.38.2"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "ntfy"
  image   = docker_image.this.image_id
  restart = "unless-stopped"
  command = ["serve"]

  memory      = 128
  memory_swap = 256

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  env = [
    "NTFY_BASE_URL=https://${local.host}",
    "NTFY_LISTEN_HTTP=:8080",
    "NTFY_BEHIND_PROXY=true",
    "NTFY_CACHE_FILE=/var/lib/ntfy/cache.db",
    "NTFY_AUTH_FILE=/var/lib/ntfy/user.db",
    "NTFY_ENABLE_LOGIN=true",
    "NTFY_AUTH_DEFAULT_ACCESS=deny-all",
    "NTFY_AUTH_USERS=${join(",", [
      "wim:${random_password.wim.bcrypt_hash}:admin",
      "gatus:${random_password.gatus.bcrypt_hash}:user",
      "donetick:${random_password.donetick.bcrypt_hash}:user",
    ])}",
    "NTFY_AUTH_ACCESS=${join(",", [
      "gatus:${local.topic}:wo",
      "donetick:${local.tasks_topic}:wo",
    ])}",
    "NTFY_AUTH_TOKENS=${join(",", [
      "gatus:tk_${random_password.gatus_token.result}:gatus",
      "donetick:tk_${random_password.donetick_token.result}:donetick",
    ])}",
    "NTFY_UPSTREAM_BASE_URL=https://ntfy.sh",
  ]

  mounts {
    type   = "bind"
    source = var.data_path
    target = "/var/lib/ntfy"
  }

  # Turns Donetick's webhook JSON into a title, a message and a priority:
  # reminders interrupt, the rest (created, completed, ...) arrives silently.
  upload {
    file    = "/etc/ntfy/templates/donetick.yml"
    content = file("${path.module}/templates/donetick.yml")
  }

  networks_advanced {
    name    = docker_network.traefik.name
    aliases = ["ntfy"]
  }

  networks_advanced {
    name    = docker_network.publishers.name
    aliases = ["ntfy"]
  }

  healthcheck {
    test = ["CMD-SHELL", "wget -q -O - http://127.0.0.1:8080/v1/health | grep -q '\"healthy\":true'"]

    interval     = "1m0s"
    timeout      = "10s"
    retries      = 3
    start_period = "20s"
  }
}

resource "docker_network" "traefik" {
  name       = "traefik-ntfy"
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false
}

resource "docker_network" "publishers" {
  name       = "ntfy-publishers"
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false
}

locals {
  host        = "ntfy.wvl.app"
  topic       = "alerts"
  tasks_topic = "tasks"
}
