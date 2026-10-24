resource "docker_network" "client" {
  for_each = var.clients

  name       = "db-${each.key}"
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

  # The entrypoint walks the data directory, which only postgres may read, as
  # root before gosu switches to postgres.
  capabilities {
    drop = ["ALL"]
    add  = ["CAP_DAC_READ_SEARCH", "CAP_SETGID", "CAP_SETUID"]
  }
  security_opts = ["no-new-privileges:true"]

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

  # One network per client, so clients reach postgres but not each other.
  dynamic "networks_advanced" {
    for_each = docker_network.client
    content {
      name    = networks_advanced.value.name
      aliases = [var.network_alias]
    }
  }

  # Block until pg_isready passes. Without it tofu returns as soon as the
  # container is created, and the zitadel roles try to connect to a postgres
  # that is still starting.
  wait = true

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready"]
    interval     = "10s"
    timeout      = "30s"
    retries      = 5
    start_period = "20s"
  }
}

output "network_names" {
  value = { for client, network in docker_network.client : client => network.name }
}
