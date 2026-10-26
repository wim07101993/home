locals {
  data_path = "/docker-volumes/adguard-home"
}

resource "docker_network" "this" {
  name       = "adguard-home"
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false
}

resource "random_password" "admin" {
  length  = 32
  special = false
}

resource "docker_image" "this" {
  name         = "adguard/adguardhome:v0.107.79"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "adguard-home"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  env = ["TZ=Europe/Brussels"]

  user = "65532:65532"

  # The binary carries cap_net_bind_service as a file capability, and the
  # kernel refuses to exec it when that is outside the bounding set.
  capabilities {
    drop = ["ALL"]
    add  = ["CAP_NET_BIND_SERVICE"]
  }
  security_opts = ["no-new-privileges:true"]

  ports {
    internal = 53
    external = var.dns_port
    protocol = "udp"
  }

  ports {
    internal = 53
    external = var.dns_port
    protocol = "tcp"
  }

  ports {
    internal = 3000
    external = var.host_port
  }

  volumes {
    host_path      = "${local.data_path}/conf"
    container_path = "/opt/adguardhome/conf"
  }

  upload {
    file = "/opt/adguardhome/conf/AdGuardHome.yaml"
    content = templatefile("${path.module}/AdGuardHome.yaml.tftpl", {
      password_hash = random_password.admin.bcrypt_hash
    })
  }

  # Blocklists, query log and statistics.
  volumes {
    host_path      = "${local.data_path}/work"
    container_path = "/opt/adguardhome/work"
  }

  networks_advanced {
    name = docker_network.this.name
  }

  # So config.tf, which runs right after a create, finds the API up.
  wait = true

  healthcheck {
    test = ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:3000/"]

    interval     = "1m0s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }
}
