resource "random_password" "jwt" {
  length  = 64
  special = false
}

resource "docker_image" "this" {
  name         = "tombursch/kitchenowl:v0.7.8"
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

    "OIDC_RFC_COMPLIANT_REDIRECT=false",

    "JWT_SECRET_KEY=${random_password.jwt.result}",

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

  mounts {
    type   = "bind"
    source = "/docker-volumes/kitchen-owl/data"
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
}
