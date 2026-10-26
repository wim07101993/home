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

resource "docker_image" "this" {
  name         = "adguard/adguardhome:v0.107.79"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "adguard-home"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  env = ["TZ=Europe/Brussels"]

  # The binary carries cap_net_bind_service as a file capability, and the
  # kernel refuses to exec it when that is outside the bounding set.
  capabilities {
    drop = ["ALL"]
    add  = ["CAP_NET_BIND_SERVICE"]
  }
  security_opts = ["no-new-privileges:true"]

  # DNS for the whole LAN, on every address: the router hands out plop as the
  # resolver. Docker DNATs published ports, so AdGuard Home sees each client's
  # own address, which is what its per-client settings key on.
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

  # The UI on the tailnet only. Published ports bypass the host firewall, so on
  # any other address the kids could reach it from the LAN.
  ports {
    internal = 3000
    external = var.host_port
    ip       = var.tailscale_ip
  }

  volumes {
    host_path      = "${local.data_path}/conf"
    container_path = "/opt/adguardhome/conf"
  }

  # Blocklists, query log and statistics.
  volumes {
    host_path      = "${local.data_path}/work"
    container_path = "/opt/adguardhome/work"
  }

  networks_advanced {
    name = docker_network.this.name
  }
}
