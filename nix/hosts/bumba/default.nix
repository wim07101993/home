{
  imports = [
    ./disko.nix
    ../../modules/base.nix
    ../../modules/hetzner.nix
    ../../modules/docker.nix
    ../../modules/tailscale.nix

    # Not ../../modules/clamav.nix: a scan holds ClamAV's signatures in memory,
    # about 1 GB (measured with clamscan 1.4.6, 2026-10-23), and bumba has 2 GB
    # and no swap, with 0.7 GB available next to zitadel and postgres. It needs
    # swap or a bigger server type first.
  ];

  networking.hostName = "bumba";

  networking.interfaces.eth0.ipv6.addresses = [{
    address = "2a01:4f8:1c17:7f63::1";
    prefixLength = 64;
  }];

  system.stateVersion = "26.05";
}
