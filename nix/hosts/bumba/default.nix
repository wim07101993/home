{
  imports = [
    ./disko.nix
    ../../modules/base.nix
    ../../modules/hetzner.nix
    ../../modules/docker.nix
    ../../modules/tailscale.nix
  ];

  networking.hostName = "bumba";

  networking.interfaces.eth0.ipv6.addresses = [{
    address = "2a01:4f8:1c17:7f63::1";
    prefixLength = 64;
  }];

  system.stateVersion = "26.05";
}
