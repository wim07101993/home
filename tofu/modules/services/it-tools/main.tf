resource "docker_image" "this" {
  name         = "corentinth/it-tools:2024.10.22-7ca5933"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "it-tools"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  capabilities {
    drop = ["ALL"]
    add  = ["CAP_CHOWN", "CAP_SETGID", "CAP_SETUID"]
  }
  security_opts = ["no-new-privileges:true"]

  networks_advanced {
    name = var.traefik_network
  }

  healthcheck {
    test = ["CMD", "curl", "-f", "http://localhost:80"]

    interval     = "1m0s"
    timeout      = "30s"
    retries      = 5
    start_period = "20s"
  }
}
