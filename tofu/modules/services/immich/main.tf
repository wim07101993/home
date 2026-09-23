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
    # Referenced, not spelled: this is what orders the role's creation before
    # the container that authenticates with it.
    "DB_USERNAME=${postgresql_role.this.name}",
    "DB_DATABASE_NAME=immich",
    "DB_PASSWORD=${random_password.db.result}",
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

  # The image's entrypoint, wrapped. See assert-superuser-password.sh: the
  # wrapper re-applies the superuser password on every start and then execs
  # docker-entrypoint.sh, which is what makes that password a tofu value
  # rather than a fact about the day the cluster was initialised.
  entrypoint = ["/bin/bash", "/usr/local/bin/assert-superuser-password.sh"]

  # The image's own CMD, reproduced. Dropping `-c config_file=` would start
  # postgres on the stock configuration instead of immich's tuned one -- which
  # is where shared_preload_libraries lives, so vchord and vectors would not
  # load and immich's search would fail against a cluster that looks healthy.
  command = ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]

  # _FILE, not the value. The image reads either; this one keeps the password
  # out of `docker inspect`. initdb still only reads it on an EMPTY data
  # directory -- the wrapper is what covers every start after the first.
  env = [
    "POSTGRES_PASSWORD_FILE=/run/secrets/postgres_superuser_password",
    # What the wrapper execs. See assert-superuser-password.sh.
    "REAL_ENTRYPOINT=/usr/local/bin/immich-docker-entrypoint.sh",
    "POSTGRES_USER=postgres",
    "POSTGRES_DB=immich",
    "POSTGRES_INITDB_ARGS=--data-checksums",
  ]

  upload {
    file       = "/usr/local/bin/assert-superuser-password.sh"
    content    = file("${path.module}/assert-superuser-password.sh")
    executable = true
  }

  upload {
    file    = "/run/secrets/postgres_superuser_password"
    content = var.superuser_password
  }

  # Healthy means BOTH postgres is accepting connections and the new password
  # is live -- the marker file is written only after the ALTER succeeds. With
  # `wait` below, that is what stops the postgresql provider from connecting
  # during the window where the container is up and still carries the old
  # password.
  healthcheck {
    # The image's own healthcheck, ANDed with the marker. Replacing it outright
    # would have thrown away whatever /usr/local/bin/healthcheck.sh knows about
    # this cluster in exchange for a pg_isready.
    test     = ["CMD-SHELL", "test -f /tmp/.superuser-password-asserted && /usr/local/bin/healthcheck.sh"]
    interval = "10s"
    timeout  = "5s"
    retries  = 12

    # Spelled the way DOCKER reports them back, not the way you would write
    # them. `60s` is stored as `1m0s`, and an unset start_interval is 5s rather
    # than 0 -- so the obvious spellings both plan an in-place update on every
    # single apply. A permanent one-resource diff is how a real change gets
    # approved by reflex.
    start_period   = "1m0s"
    start_interval = "5s"
  }

  # Blocks the apply until the above passes. Costs a few seconds on every
  # replacement and removes the race entirely.
  wait         = true
  wait_timeout = 180

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

  # The library. Local since 2026-09-18; see var.library_path. rslave is kept
  # but no longer load-bearing -- it mattered when this was NFS. Unlike
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

# GENERATED. The password for the `immich` role in database.tf -- an ordinary
# rotatable credential since 2026-09-23.
#
# It used to be the postgres SUPERUSER's password, adopted with
# `ignore_changes = all` because `POSTGRES_PASSWORD` is only read by initdb on
# an EMPTY data directory, so tofu could set the container env and nothing
# else. That value now lives in var.superuser_password.
#
# Rotating is one command, and the provider issues the ALTER ROLE itself:
#
#   tofu apply -replace='module.immich.random_password.db'
#
resource "random_password" "db" {
  length = 32

  # No `ignore_changes` any more. It was there to suppress the replacement an
  # imported random_password plans when the config's generation attributes do
  # not match the adopted value -- which was correct while a replacement would
  # have changed the container env and NOT the database. Now a replacement
  # changes both, in one apply, which is the whole point.
}
