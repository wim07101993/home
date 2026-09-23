# Home Assistant and the Matter server, on plop.
#
# plop is the house: a Debian box on the home LAN with the USB radio attached.
# It is the last host to come into tofu, and the only one whose services are
# reached over the tailnet rather than through a reverse proxy -- there is no
# traefik here and Home Assistant is on 8123 directly.
#
# A CUTOVER from the Portainer stack `homeassistant`, which must be DELETED
# THERE FIRST. Read README.md before doing that: the Matter data has to be
# rescued out of an anonymous volume beforehand, and deleting the stack is what
# can destroy it.

resource "docker_network" "this" {
  name       = "homeassistant_home-assistant-network"
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false
}

# --- home assistant ------------------------------------------------------

resource "docker_image" "this" {
  name         = "homeassistant/home-assistant:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "this" {
  # Was `homeassistant-homeassistant-1` -- compose's <project>-<service>-<n>.
  # Renamed because nothing depends on it: Home Assistant is reached on the
  # host port, not by container name, and matterjs-server is on host
  # networking.
  name    = "home-assistant"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  env = ["TZ=Europe/Brussels"]

  security_opts = ["no-new-privileges:true"]

  capabilities {
    drop = ["ALL"]
  }

  # From the compose `deploy.resources.limits`. plop is not shared with
  # anything else, so these are a blast radius rather than a quota: a runaway
  # integration should not take the box down with it.
  #
  # NOT REPRODUCED: `pids: 99`. kreuzwerker/docker has no attribute for the
  # cgroup PidsLimit -- its `ulimit` block sets per-process rlimits, which is a
  # different mechanism and not a substitute. So this container loses a fork
  # bomb guard the compose stack had. Recorded rather than quietly dropped;
  # see README.md.
  #
  # "6.0" and an explicit memory_swap, spelled the way DOCKER reports them
  # back. `cpus = "6"` reads as a change to "6.0" that FORCES REPLACEMENT, and
  # an omitted memory_swap is computed as 2x memory and then planned away --
  # so the obvious spellings rebuild both containers on every apply, which for
  # this module means restarting the house.
  memory      = 8192
  memory_swap = 16384
  cpus        = "6.0"

  ports {
    internal = 8123
    external = 8123
  }

  volumes {
    host_path      = var.config_path
    container_path = "/config"
  }

  # GENERATED, and written THROUGH the bind above -- verified 2026-09-23 that
  # an upload under a directory bind lands on the host rather than being
  # shadowed by it. (A bind of the FILE itself would shadow it; a bind of the
  # containing directory does not.)
  #
  # So this file is owned by tofu and overwritten on every container create.
  # Home Assistant never rewrites configuration.yaml itself -- it writes
  # .storage/ and the recorder database -- so nothing of its own is lost.
  # Anything hand-edited on plop IS lost, which is the intended trade.
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
  name         = "ghcr.io/matter-js/matterjs-server:${var.matter_image_tag}"
  keep_locally = true
}

resource "docker_container" "matter" {
  name    = "matterjs-server"
  image   = docker_image.matter.image_id
  restart = "unless-stopped"

  # Matter is IPv6 multicast on the LAN. A bridge does not carry it, so this
  # cannot move off host networking without breaking commissioning.
  network_mode = "host"

  read_only     = true
  security_opts = ["no-new-privileges:true"]

  capabilities {
    drop = ["ALL"]
  }

  # See the note on the Home Assistant container: `pids: 99` cannot be
  # expressed by this provider and is lost here too, and the same spellings
  # are needed to stop a replacement on every apply.
  memory      = 8192
  memory_swap = 16384
  cpus        = "6.0"

  # /data, NOT /data". The compose file had a stray quote --
  #
  #     - /docker-volumes/homeassistant/matterjs-server:/data"
  #
  # -- so this bind landed on a path nothing reads, and because the image
  # declares VOLUME /data docker quietly supplied an anonymous volume instead.
  # The Matter fabric has been living there since 2026-06-30. See README.md;
  # the data must be copied across BEFORE this is applied.
  volumes {
    host_path      = var.matter_data_path
    container_path = "/data"
  }
}
