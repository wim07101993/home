resource "docker_image" "this" {
  name         = "neosmemo/memos:0.26.2"
  keep_locally = true
}

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

  capabilities {
    drop = ["ALL"]
    add  = ["CAP_SETGID", "CAP_SETUID"]
  }
  security_opts = ["no-new-privileges:true"]

  ports {
    internal = 5230
    external = 5230
  }

  # TODO why is this here?
  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/var/opt/memos"
  }

  networks_advanced {
    name    = var.traefik_network
    aliases = ["memo"]
  }

  networks_advanced {
    name    = var.db_network
    aliases = ["memo"]
  }
}
