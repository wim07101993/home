resource "docker_image" "this" {
  name         = "donetick/donetick:v0.1.89"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "donetick"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  memory      = 256
  memory_swap = 512

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  env = ["DT_ENV=selfhosted"]

  upload {
    file = "/config/selfhosted.yaml"
    content = templatefile("${path.module}/selfhosted.yaml.tftpl", {
      host          = local.host
      db_user       = postgresql_role.this.name
      db_password   = random_password.db.result
      db_name       = postgresql_database.this.name
      jwt_secret    = random_password.jwt.result
      client_id     = zitadel_application_oidc.this.client_id
      client_secret = zitadel_application_oidc.this.client_secret
    })
  }

  networks_advanced {
    name    = docker_network.traefik.name
    aliases = ["donetick"]
  }

  networks_advanced {
    name    = var.db_network
    aliases = ["donetick"]
  }

  healthcheck {
    test = ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:2021/api/v1/health"]

    interval     = "1m0s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }
}

resource "docker_network" "traefik" {
  name       = "traefik-donetick"
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false
}

resource "random_password" "jwt" {
  length  = 48
  special = false
}

locals {
  host = "tasks.wvl.app"
}
