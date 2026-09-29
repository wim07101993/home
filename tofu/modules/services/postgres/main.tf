resource "docker_network" "this" {
  name       = "db-network"
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false
}

resource "docker_image" "postgres" {
  name         = "postgres:17.10-alpine3.23"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "db"
  image   = docker_image.postgres.image_id
  restart = "unless-stopped"

  env = [
    "PGUSER=postgres",
    "POSTGRES_PASSWORD_FILE=/run/secrets/db_password",
    "PGDATA=/data/postgres",
  ]

  ports {
    internal = 5432
    external = var.host_port
  }

  volumes {
    host_path      = "/docker-volumes/db/data"
    container_path = "/data/postgres"
  }

  volumes {
    host_path      = "/docker-volumes/db/db_password.txt"
    container_path = "/run/secrets/db_password"
    read_only      = true
  }

  networks_advanced {
    name    = docker_network.this.name
    aliases = [var.network_alias]
  }

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready"]
    interval     = "10s"
    timeout      = "30s"
    retries      = 5
    start_period = "20s"
  }
}

output "network_name" {
  value = docker_network.this.name
}
