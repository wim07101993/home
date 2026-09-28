resource "docker_network" "this" {
  name       = "home-assistant"
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false
}

# --- home assistant ------------------------------------------------------

resource "docker_image" "this" {
  name         = "homeassistant/home-assistant:2026.6.4"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "home-assistant"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  env = ["TZ=Europe/Brussels"]

  security_opts = ["no-new-privileges:true"]

  capabilities {
    drop = ["ALL"]
  }

  ports {
    internal = 8123
    external = 8123
  }

  volumes {
    host_path      = "/docker-volumes/homeassistant/config"
    container_path = "/config"
  }

  upload {
    file = "/config/configuration.yaml"
    content = templatefile("${path.module}/configuration.yaml.tftpl", {
      client_id     = zitadel_application_oidc.this.client_id
      client_secret = zitadel_application_oidc.this.client_secret
      tailscale_ip  = var.tailscale_ip
    })
  }

  # Host time and the system bus. dbus is what lets Home Assistant see
  # Bluetooth adapters on the host.
  volumes {
    host_path      = "/etc/localtime"
    container_path = "/etc/localtime"
    read_only      = true
  }

  volumes {
    host_path      = "/run/dbus"
    container_path = "/run/dbus"
    read_only      = true
  }

  devices {
    host_path      = var.serial_device
    container_path = var.serial_device
    permissions    = "rwm"
  }

  networks_advanced {
    name = docker_network.this.name
  }
}

# --- matter server -------------------------------------------------------

resource "docker_image" "matter" {
  name         = "ghcr.io/matter-js/matterjs-server:1.1.5"
  keep_locally = true
}

resource "docker_container" "matter" {
  name    = "matterjs-server"
  image   = docker_image.matter.image_id
  restart = "unless-stopped"

  network_mode = "host"

  read_only     = true
  security_opts = ["no-new-privileges:true"]

  capabilities {
    drop = ["ALL"]
  }

  volumes {
    host_path      = "/docker-volumes/homeassistant/matterjs-server"
    container_path = "/data"
  }
}
