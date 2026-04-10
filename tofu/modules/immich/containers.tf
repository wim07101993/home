resource "docker_service" "immich_server" {
  name = "immich-server"

  task_spec {
    container_spec {
      image = "ghcr.io/immich-app/immich-server:v2.6.3"
      env = {
        IMMICH_VERSION     = "v2.6.3"
        UPLOAD_LOCATION    = "/data"
        DB_PASSWORD        = var.db_password
        DB_USERNAME        = "immich"
        DB_DATABASE_NAME   = "immich"
        DB_HOSTNAME        = "immich-postgres"
        REDIS_HOSTNAME     = "immich-redis"
      }

      mounts {
        type   = "bind"
        source = "/docker-volumes/immich/upload"
        target = "/data"
      }
      mounts {
        type   = "bind"
        source = "/etc/localtime"
        target = "/etc/localtime"
        read_only = true
      }
    }

    networks_advanced { name = var.traefik_network }
    networks_advanced { name = docker_network.immich_internal.name }
  }

  labels {
    label = "traefik.enable"
    value = "true"
  }
  labels {
    label = "traefik.http.routers.photos.rule"
    value = "Host(`photos.${var.domain}`)"
  }
  labels {
    label = "traefik.http.routers.photos.entrypoints"
    value = "websecure"
  }
  labels {
    label = "traefik.http.routers.photos.tls.certresolver"
    value = "le"
  }
}

resource "docker_service" "immich_ml" {
  name = "immich-ml"

  task_spec {
    container_spec {
      image = "ghcr.io/immich-app/immich-machine-learning:v2.6.3"
    }
    networks_advanced { name = docker_network.immich_internal.name }
  }
}

resource "docker_service" "immich_redis" {
  name = "immich-redis"

  task_spec {
    container_spec {
      image = "docker.io/valkey/valkey:9"
    }
    networks_advanced { name = docker_network.immich_internal.name }
  }
}

resource "docker_service" "immich_postgres" {
  name = "immich-postgres"

  task_spec {
    container_spec {
      image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0"
      env = {
        POSTGRES_PASSWORD = var.db_password
        POSTGRES_USER     = "immich"
        POSTGRES_DB       = "immich"
      }
      mounts {
        type   = "bind"
        source = "/docker-volumes/immich/postgres"
        target = "/var/lib/postgresql/data"
      }
    }
    networks_advanced { name = docker_network.immich_internal.name }
  }
}
