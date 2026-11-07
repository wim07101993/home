resource "docker_image" "this" {
  name         = "ghcr.io/jeffvli/feishin:1.17.0"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "feishin"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  env = [
    # Pinned to navidrome, so users enter only a username and password.
    "SERVER_NAME=music",
    "SERVER_TYPE=navidrome",
    "SERVER_URL=https://music.wvl.app",
    "SERVER_LOCK=true",

    # On by default: usage analytics to Feishin's Umami.
    "ANALYTICS_DISABLED=true",
  ]

  networks_advanced {
    name = docker_network.traefik.name
  }

  healthcheck {
    test = ["CMD", "wget", "-q", "--spider", "http://localhost:9180/"]

    interval     = "1m0s"
    timeout      = "10s"
    retries      = 3
    start_period = "10s"
  }
}

# Shared with traefik and nothing else.
resource "docker_network" "traefik" {
  name       = "traefik-feishin"
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false
}
