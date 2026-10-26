{
  imports = [
    ./disko.nix
    ../../modules/base.nix
    ../../modules/auto-update.nix
    ../../modules/hetzner.nix
    ../../modules/docker.nix
    ../../modules/tailscale.nix
    ../../modules/clamav.nix
  ];

  networking.hostName = "bumba";

  networking.interfaces.eth0.ipv6.addresses = [{
    address = "2a01:4f8:1c17:7f63::1";
    prefixLength = 64;
  }];

  # gatus checks databasus's health endpoint on samson. See docker.nix.
  homelab.containers.reachableOnTailnet = [
    { address = "100.71.248.106"; port = 4005; }
  ];

  # tofu's traefik runs as 65532 in the remapped namespace: 231068 here. `Z`
  # re-owns its certificates on every boot and rebuild, keeping acme.json 0600.
  systemd.tmpfiles.rules = [
    "d /docker-volumes/traefik 0755 root root -"
    "d /docker-volumes/traefik/letsencrypt 0755 231068 231068 -"
    "Z /docker-volumes/traefik/letsencrypt - 231068 231068 -"
  ];

  system.stateVersion = "26.05";
}
