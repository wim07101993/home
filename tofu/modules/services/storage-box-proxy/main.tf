
locals {
  target_port = 23
}

resource "docker_image" "this" {
  name         = "alpine/socat:1.8.0.3"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "storage-box-proxy"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  command = [
    "TCP-LISTEN:${var.listen_port},fork,reuseaddr",
    "TCP:${var.target_host}:${local.target_port}",
  ]

  security_opts = ["no-new-privileges:true"]

  memory      = 64
  memory_swap = 128

  ports {
    internal = var.listen_port
    external = var.listen_port
    ip       = var.tailscale_ip
  }
}
