resource "docker_image" "this" {
  name         = "neosmemo/memos:0.31.0"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "memos"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  env = [
    "MEMOS_DRIVER=postgres",
    "MEMOS_DSN_FILE=/run/secrets/db_connection_string",
  ]

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

  user = "10001:10001"

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  ports {
    internal = 5230
    external = var.host_port
  }

  networks_advanced {
    name    = docker_network.traefik.name
    aliases = ["memo"]
  }

  networks_advanced {
    name    = var.db_network
    aliases = ["memo"]
  }
}

# Shared with traefik and nothing else.
resource "docker_network" "traefik" {
  name       = "traefik-memos"
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false
}
