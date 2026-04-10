resource "docker_service" "db" {
  name = "db"

  task_spec {
    container_spec {
      image = "postgres:17.9-alpine3.23"

      env = {
        PGUSER                 = "postgres"
        POSTGRES_PASSWORD_FILE = "/run/secrets/db_password"
        PGDATA                 = "/data/postgres"
      }

      mounts {
        type   = "bind"
        source = "/docker-volumes/db/data"
        target = "/data/postgres"
      }

      secrets {
        secret_id   = docker_secret.db_password.id
        secret_name = docker_secret.db_password.name
        file_name   = "db_password"
      }

      healthcheck {
        test     = ["CMD-SHELL", "pg_isready"]
        interval = "10s"
        timeout  = "30s"
        retries  = 5
      }
    }

    networks_advanced {
      name = var.db_network_id
    }
  }

  endpoint_spec {
    ports {
      target_port    = 5432
      published_port = 5432
      publish_mode   = "host"
    }
  }
}
