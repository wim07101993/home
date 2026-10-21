{
  imports = [
    ./disko.nix
    ../../modules/base.nix
    ../../modules/hetzner.nix
    ../../modules/docker.nix
    ../../modules/tailscale.nix
  ];

  networking.hostName = "rehearsal";

  # No static IPv6: this host is disposable. Everything else is bumba verbatim.

  system.stateVersion = "26.05";
}
