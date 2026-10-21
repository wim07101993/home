{ config, ... }:

{
  services.tailscale.enable = true;

  networking.firewall = {
    allowedUDPPorts = [ config.services.tailscale.port ];
    checkReversePath = "loose";
  };

  # Not authenticated declaratively: `tailscale up` once per host, interactively.
  # An auth key in this repo would be a secret in a public repository, and the
  # node key it mints outlives the auth key anyway.
}
