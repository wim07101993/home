# memo.wvl.app -- memos, on mindy. Postgres-backed.
#
# This is the app that proved the whole zitadel approach: it stores the OIDC
# `sub` as the account's username, so the 45 notes survive only because users
# were never recreated. Its OIDC cutover to the new client id is separate from
# this container migration and can happen independently.

# The role and database live in ../../databases, adopted there on 2026-09-18 --
# the last database in the estate tofu did not know about. They arrive here as
# var.db_*.
#
# Until then this module bind-mounted var.dsn_file from mindy's disk, so the
# credential existed only on that host: unversioned, unreproducible, and a
# rebuilt postgres would have left memos pointing at a database nothing
# declared. The same shape as the incident in
# ../../../../docs/data-architecture.md, where memos ran for months against an
# EMPTY database, because "app up, database present" is not the same claim as
# "app connected to the right database".

resource "docker_image" "this" {
  name         = "neosmemo/memos:${var.image_tag}"
  keep_locally = true
}

# The image declares VOLUME /var/opt/memos, so docker creates an ANONYMOUS
# volume if nothing is mounted there. Compose let it. That is a latent
# data-loss bug: `remove_volumes` defaults to true, so every container
# replacement discards it -- and replacement now happens on any config change.
#
# It is empty today (4 KB, nothing but the directory) because the postgres
# driver keeps everything in the database, attachments included. Which makes
# this the one moment when naming it costs nothing: there is no data to
# migrate, and if memos ever starts writing there it will already be safe.
resource "docker_volume" "data" {
  name = "memos_data"

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_container" "this" {
  name    = "memos"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  env = [
    "MEMOS_DRIVER=postgres",
    "MEMOS_DSN_FILE=/run/secrets/db_connection_string",
  ]

  # Generated, not bind-mounted. `host=db` is the network alias of mindy's
  # postgres on db_db-network.
  upload {
    file = "/run/secrets/db_connection_string"
    content = join(" ", [
      "user=${postgresql_role.this.name}",
      "password=${random_password.db.result}",
      "host=db",
      "port=5432",
      "dbname=${postgresql_database.this.name}",
      "sslmode=disable",
    ])
  }

  # CAP_ prefixes are required -- docker stores the canonical form and the
  # provider diffs against it. Bare `SETGID` recreates the container on every
  # apply, forever.
  capabilities {
    drop = ["ALL"]
    add  = ["CAP_SETGID", "CAP_SETUID"]
  }
  security_opts = ["no-new-privileges:true"]

  # `deploy.resources.limits.pids: 99` is not reproducible: kreuzwerker/docker
  # has no pids_limit. See modules/services/it-tools/main.tf for why
  # `ulimit { name = "nproc" }` is not a substitute.

  ports {
    internal = 5230
    external = var.host_port
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/var/opt/memos"
  }

  # traefik reaches it here.
  networks_advanced {
    name    = var.traefik_network
    aliases = ["memo"]
  }

  # postgres lives here. Without this, memos cannot start.
  networks_advanced {
    name    = var.db_network
    aliases = ["memo"]
  }

  # Compose also made `memos_memo-network` -- a private bridge with one
  # container and no peers. An artifact of compose's per-project model, not a
  # feature; left orphaned by the cutover and removable afterwards.

  # The var.db_* values in the DSN above already order this after
  # ../../databases.
}
