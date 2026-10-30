resource "docker_image" "this" {
  name         = "restic/rest-server:0.14.0"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "rest-server"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  # Past the image's entrypoint script, which creates an empty .htpasswd in the
  # data directory when there is none.
  entrypoint = [
    "rest-server",
    "--path", "/data",
    "--htpasswd-file", "/etc/rest-server/htpasswd",
    # Each client reaches only /<its name>/.
    "--private-repos",
  ]

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  memory      = 512
  memory_swap = 1024

  ports {
    internal = 8000
    external = var.port
    ip       = var.tailscale_ip
  }

  upload {
    file    = "/etc/rest-server/htpasswd"
    content = join("", [for client in var.clients : "${client.username}:${client.bcrypt_hash}\n"])
  }

  mounts {
    type   = "bind"
    source = var.data_path
    target = "/data"
  }
}
