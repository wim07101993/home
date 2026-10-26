resource "docker_image" "this" {
  name         = "corentinth/it-tools:2024.10.22-7ca5933"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "it-tools"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  user = "101:101"
  tmpfs = {
    "/var/cache/nginx" = "uid=101,gid=101"
    "/run"             = "uid=101,gid=101"
  }

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  networks_advanced {
    name = docker_network.traefik.name
  }

  healthcheck {
    test = ["CMD", "curl", "-f", "http://localhost:80"]

    interval     = "1m0s"
    timeout      = "30s"
    retries      = 5
    start_period = "20s"
  }
}

# Shared with traefik and nothing else.
resource "docker_network" "traefik" {
  name       = "traefik-it-tools"
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false
}
