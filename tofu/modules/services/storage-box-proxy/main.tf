# A TCP forwarder on bumba, so samson and plop can reach the Storage Box.
#
# THE PROBLEM IT SOLVES. snow-white has access_settings.reachable_externally =
# false, and Hetzner offers no IP allowlist -- the setting is binary. That is
# not a firewall: verified 2026-09-23 that the TCP connection completes and SSH
# negotiates from anywhere. What the box does is refuse to OFFER any
# authentication method to a client outside Hetzner:
#
#   from mindy / bumba   Permission denied (publickey,password)
#   from samson / plop   Permission denied ()
#
# So a client at home can never authenticate, however correct its credentials.
# Forwarding through a Hetzner host makes the connection arrive from an address
# the box trusts, and auth proceeds normally.
#
# WHY NOT THE ALTERNATIVES:
#
#   reachable_externally = true   puts the repository on the public internet.
#                                 kopia encrypts, so the risk is deletion, not
#                                 disclosure -- and the SFTP credential can
#                                 delete regardless of delete_protection.
#   tailscale subnet router       needs route advertisement on the host, an API
#                                 credential that expires, tags, and the ACL.
#                                 Four prerequisites for one hop.
#   ssh ProxyJump                 needs externalSSH on every client and
#                                 ssh_keys on the Storage Box -- the one
#                                 attribute that forces replacement of the
#                                 resource holding every backup.
#
# This is a container with one command in it.
resource "docker_image" "this" {
  name         = "alpine/socat:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "storage-box-proxy"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  # The image's entrypoint IS socat, so this is its argument list.
  #
  # `fork` because each client opens its own connection and without it the
  # second one waits for the first to finish -- which, for a backup, is
  # forever. `reuseaddr` so a restart does not wait out TIME_WAIT.
  command = [
    "TCP-LISTEN:${var.listen_port},fork,reuseaddr",
    "TCP:${var.target_host}:${var.target_port}",
  ]

  security_opts = ["no-new-privileges:true"]

  # bumba is a cpx11 with 2 GB shared with zitadel, postgres and traefik. socat
  # copies bytes; it does not need more than this, and capping it means a
  # backup cannot be the reason something else is killed.
  memory      = 64
  memory_swap = 128

  # BOUND TO THE TAILNET ADDRESS, not 0.0.0.0. Without the `ip`, this is an
  # unauthenticated relay into a Storage Box whose only access control is where
  # the packet came from -- it would hand the whole internet exactly what
  # reachable_externally = false exists to prevent.
  ports {
    internal = var.listen_port
    external = var.listen_port
    ip       = var.tailscale_ip
  }
}
