# keuken.wvl.app -- KitchenOwl on mindy.
#
# Moved off its own postgres:15 onto mindy's shared postgres 17 on 2026-09-17,
# and onto the rebuilt zitadel app in the same change.
#
# The move was nearly free because KitchenOwl reaches its database as `db`,
# which is a network alias -- and the shared postgres answers to the same name.
# Attaching to db_db-network instead of its own network is most of the work.
#
# The role and database live in ../../databases and arrive as var.db_*.
# random_password.jwt stays here: it is not a database credential.

# WAS `PLEASE_CHANGE_ME`.
#
# That is the image's default, published in the Dockerfile, and it had never
# been overridden. It signs KitchenOwl's session tokens, so anyone who could
# reach keuken.wvl.app could forge a session for any user --
# DISABLE_USERNAME_PASSWORD_LOGIN does not help, because a forged token skips
# login entirely.
#
# Generating it here means it is never a default again, and never typed by
# anyone. Rotating it logs everybody out; nothing worse.
resource "random_password" "jwt" {
  length  = 64
  special = false
}

resource "docker_image" "this" {
  name         = "tombursch/kitchenowl:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "kitchen-owl"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  env = [
    "FRONT_URL=https://keuken.wvl.app",
    "DISABLE_USERNAME_PASSWORD_LOGIN=true",

    "OIDC_ISSUER=https://auth.wvl.app",
    "OIDC_NAME=Home",
    "OIDC_CLIENT_ID=${zitadel_application_oidc.this.client_id}",
    "OIDC_CLIENT_SECRET=${zitadel_application_oidc.this.client_secret}",

    # Set on the live container but in neither the compose file nor its .env --
    # a portainer stack override, invisible to the repo. Reproduced from what
    # was actually running.
    "OIDC_RFC_COMPLIANT_REDIRECT=false",

    "JWT_SECRET_KEY=${random_password.jwt.result}",

    # `db` is the shared postgres's network alias on db_db-network. Same name
    # its own postgres used, which is why nothing else here changes.
    "DB_DRIVER=postgresql",
    "DB_HOST=db",
    "DB_PORT=5432",
    "DB_NAME=${postgresql_database.this.name}",
    "DB_USER=${postgresql_role.this.name}",
    "DB_PASSWORD=${random_password.db.result}",
  ]

  capabilities {
    drop = ["ALL"]
    add  = ["CAP_SETGID", "CAP_SETUID"]
  }
  security_opts = ["no-new-privileges:true"]

  # `pids: 99` is not reproducible -- see ../it-tools/main.tf.

  ports {
    internal = 8080
    external = var.host_port
  }

  mounts {
    type   = "bind"
    source = var.data_path
    target = "/data"
  }

  networks_advanced {
    name    = var.traefik_network
    aliases = ["kitchen-owl"]
  }

  networks_advanced {
    name    = var.db_network
    aliases = ["kitchen-owl"]
  }

  # No depends_on: the var.db_* values in env already order this module after
  # ../../databases.
}
