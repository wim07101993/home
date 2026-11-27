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

  # gatus checks the health endpoints of databasus and rest-server on samson.
  # See docker.nix.
  homelab.containers.reachableOnTailnet = [
    { address = "100.71.248.106"; port = 4005; }
    { address = "100.71.248.106"; port = 8000; }
  ];

  systemd.tmpfiles.rules = [
    # tofu's traefik runs as 65532 in the remapped namespace: 231068 here. `Z`
    # re-owns its certificates on every boot and rebuild, keeping acme.json 0600.
    "d /docker-volumes/traefik 0755 root root -"
    "d /docker-volumes/traefik/letsencrypt 0755 231068 231068 -"
    "Z /docker-volumes/traefik/letsencrypt - 231068 231068 -"

    # tofu's ntfy runs as root in the remapped namespace: 165536 here.
    "d /docker-volumes/ntfy 0755 root root -"
    "d /docker-volumes/ntfy/data 0700 165536 165536 -"
  ];

  system.stateVersion = "26.05";
}
