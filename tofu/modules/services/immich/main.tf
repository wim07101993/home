# photos.wvl.app -- immich on mindy. Four containers.
#
# The library is NFS from samson (100.71.248.106:/export/photos). The database
# is immich's own postgres with vectorchord, entirely separate from the
# estate's postgres, and its data is a bind mount.

resource "docker_network" "internal" {
  name       = "immich_immich-network"
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false

  # Reproduced exactly so the import plans clean -- a missing label forces
  # replacement, and all four containers hang off this.
  labels {
    label = "com.docker.compose.config-hash"
    value = "06395b0762b0ec18b286d2cc1f73d65310c55db31fdd9b36ee164228ef5944f1"
  }
  labels {
    label = "com.docker.compose.network"
    value = "immich-network"
  }
  labels {
    label = "com.docker.compose.project"
    value = "immich"
  }
  labels {
    label = "com.docker.compose.version"
    value = ""
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Imported, not created: it holds the downloaded ML models. Recreating it means
# immich re-downloads several GB on first use.
resource "docker_volume" "model_cache" {
  name = "immich_model-cache"

  labels {
    label = "com.docker.compose.config-hash"
    value = "f9b1e6c118142cab8e2dc4356da9a09ffca54c5e0f80145d438e4c4a9bc909a8"
  }
  labels {
    label = "com.docker.compose.project"
    value = "immich"
  }
  labels {
    label = "com.docker.compose.version"
    value = ""
  }
  labels {
    label = "com.docker.compose.volume"
    value = "model-cache"
  }

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  # env_file loaded all of these into every container. UPLOAD_LOCATION and
  # DB_DATA_LOCATION are compose interpolation variables that the application
  # itself does not read -- it uses /data and PGDATA. They are kept for
  # parity, but with the CORRECT paths rather than the broken one the live
  # container carries.
  shared_env = [
    "DB_USERNAME=postgres",
    "DB_DATABASE_NAME=immich",
    "DB_PASSWORD=${var.db_password}",
    "UPLOAD_LOCATION=${var.library_path}",
    "DB_DATA_LOCATION=${var.db_data_path}",
  ]
}

# --- database -----------------------------------------------------------

resource "docker_image" "postgres" {
  name         = var.postgres_image
  keep_locally = true
}

resource "docker_container" "postgres" {
  name    = "immich_postgres"
  image   = docker_image.postgres.image_id
  restart = "always"

  env = [
    "POSTGRES_PASSWORD=${var.db_password}",
    "POSTGRES_USER=postgres",
    "POSTGRES_DB=immich",
    "POSTGRES_INITDB_ARGS=--data-checksums",
  ]

  security_opts = ["no-new-privileges:true"]

  # memory_swap is docker's 2x default. Omitting it does not mean "unset" --
  # docker computes it, reports it back, and the provider then plans to null
  # it every single time. An in-place update rather than a replacement, so it
  # never breaks anything; it just never settles either.
  memory      = 4096
  memory_swap = 8192
  shm_size    = 128

  ports {
    internal = 5432
    external = 5434
  }

  volumes {
    host_path      = var.db_data_path
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name    = docker_network.internal.name
    aliases = ["database"]
  }
}

# --- redis --------------------------------------------------------------

resource "docker_image" "redis" {
  name         = var.redis_image
  keep_locally = true
}

resource "docker_container" "redis" {
  name    = "immich_redis"
  image   = docker_image.redis.image_id
  restart = "always"

  capabilities {
    drop = ["ALL"]
    add  = ["CAP_SETGID", "CAP_SETUID"]
  }
  security_opts = ["no-new-privileges:true"]
  memory        = 2048
  memory_swap   = 4096 # docker's 2x default -- see the postgres container

  networks_advanced {
    name    = docker_network.internal.name
    aliases = ["redis"]
  }

  # The compose stack set only `test`, leaving docker to apply its defaults.
  # They are spelled out here because the provider compares what it reads back
  # against what the config says: leaving them at 0s means docker reports 30s
  # and the container is replaced on every apply, forever. Same trap the
  # capability names set in ../it-tools/main.tf.
  healthcheck {
    test         = ["CMD-SHELL", "redis-cli ping || exit 1"]
    interval     = "30s"
    timeout      = "30s"
    retries      = 3
    start_period = "0s"
  }
}

# --- machine learning ---------------------------------------------------

resource "docker_image" "machine_learning" {
  name         = "ghcr.io/immich-app/immich-machine-learning:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "machine_learning" {
  name    = "immich_machine_learning"
  image   = docker_image.machine_learning.image_id
  restart = "always"

  env = local.shared_env

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]
  memory        = 4096
  memory_swap   = 8192

  volumes {
    volume_name    = docker_volume.model_cache.name
    container_path = "/cache"
  }

  networks_advanced {
    name    = docker_network.internal.name
    aliases = ["immich-machine-learning"]
  }
}

# --- server -------------------------------------------------------------

resource "docker_image" "server" {
  name         = "ghcr.io/immich-app/immich-server:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "server" {
  name    = "immich"
  image   = docker_image.server.image_id
  restart = "always"

  env = local.shared_env

  security_opts = ["no-new-privileges:true"]
  memory        = 4096
  memory_swap   = 8192

  ports {
    internal = 2283
    external = 2283
  }

  # The NFS library. rslave is not strictly required here -- unlike
  # file-browser's nine automounts, this one is mounted at boot, before docker
  # starts -- but it costs nothing and removes the dependency on that ordering.
  mounts {
    type   = "bind"
    source = var.library_path
    target = "/data"

    bind_options {
      propagation = "rslave"
    }
  }

  mounts {
    type      = "bind"
    source    = "/etc/localtime"
    target    = "/etc/localtime"
    read_only = true
  }

  networks_advanced {
    name    = docker_network.internal.name
    aliases = ["immich-server"]
  }

  networks_advanced {
    name    = var.traefik_network
    aliases = ["immich"]
  }

  depends_on = [
    docker_container.postgres,
    docker_container.redis,
  ]
}
