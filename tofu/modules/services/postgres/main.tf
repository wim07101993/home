# A postgres container. One instance per host.
#
# bumba: zitadel's database, score's, and THIS LAYER'S OWN STATE. Recreating it
# needs the state round-trip documented above the backend block in
# ../../../providers.tf -- read that first.
#
# mindy: memos and filebrowser. No state, no round-trip, and the postgresql
# provider does not point here, so a plain apply works.

resource "docker_network" "this" {
  name       = var.network_name
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false

  dynamic "labels" {
    for_each = var.network_labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  lifecycle {
    # zitadel and score are still compose-managed and attach to this by name.
    prevent_destroy = true
  }
}

resource "docker_image" "postgres" {
  name         = "postgres:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = var.container_name
  image   = docker_image.postgres.image_id
  restart = "unless-stopped"

  env = [
    "PGUSER=postgres",
    "POSTGRES_PASSWORD_FILE=/run/secrets/db_password",
    "PGDATA=/data/postgres",
  ]

  # Like-for-like with compose, which binds 0.0.0.0.
  #
  # On bumba the only thing keeping this off the internet is firewall-1, which
  # allows 80, 443 and icmp and nothing else. Narrowing to 127.0.0.1 plus the
  # tailnet address would make that two independent layers, and it is a
  # one-line change here -- but deliberately not bundled into a migration,
  # where a failure would be ambiguous.
  ports {
    internal = 5432
    external = 5432
  }

  volumes {
    host_path      = var.data_path
    container_path = "/data/postgres"
  }

  # Compose called this a `secret`; without swarm that is a read-only bind
  # mount either way, so this is the same thing said plainly.
  volumes {
    host_path      = var.password_file
    container_path = "/run/secrets/db_password"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.this.name

    # See variables.tf. Without this, zitadel's `Host: 'db'` resolves to
    # nothing.
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

# So dependent service modules can reference the network rather than naming it
# as a string.
output "network_name" {
  value = docker_network.this.name
}
