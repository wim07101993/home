{
  imports = [
    ./disko.nix
    ./hardware.nix
    ./storage.nix
    ../../modules/base.nix
    ../../modules/docker.nix
    ../../modules/tailscale.nix
    ../../modules/clamav.nix
  ];

  networking.hostName = "samson";

  # Physical host on the LAN: DHCP on the onboard NIC, no static addressing.
  networking.useDHCP = false;
  networking.interfaces.eno1.useDHCP = true;

  # plex and tofu's ftp container run with host networking, so their ports are
  # the host's and the firewall sees them. Opened on eno1 only, which keeps
  # samson's own containers off them; the tailnet is trusted anyway.
  networking.firewall.interfaces.eno1 = {
    # plex: 32400 is the server itself, which the router also forwards for
    # remote access (manual port mapping); 32410-32414/udp is LAN discovery
    # (GDM). DLNA is off in plex, so 1900/udp and 32469 stay closed.
    #
    # ftp: 21 for control and a fixed passive range for data (the module's
    # passive_ports).
    allowedTCPPorts = [ 21 32400 ];
    allowedTCPPortRanges = [{ from = 21000; to = 21010; }];
    allowedUDPPorts = [ 32410 32412 32413 32414 ];
  };

  # What samson's containers may reach on the tailnet. See docker.nix.
  homelab.containers.reachableOnTailnet = [
    # databasus: the postgres clusters it backs up.
    { address = "100.127.106.121"; port = 5432; } # mindy
    { address = "100.127.106.121"; port = 5434; } # mindy, immich's
    { address = "100.104.241.49"; port = 5432; } # bumba

    # backrest: the Storage Box through bumba's proxy, and sync to mindy's.
    { address = "100.104.241.49"; port = 2223; }
    { address = "100.127.106.121"; port = 9898; }
  ];

  programs.msmtp = {
    enable = true;
    setSendmail = true;
    accounts.default = {
      host = "127.0.0.1";
      port = 2525;
      from = "samson@mail.wvl.app";
      auth = false;
      tls = false;
    };
  };

  # navidrome runs remapped: its root is 165536 on this host. `Z` re-owns its
  # volumes on every boot and rebuild, so a restore comes out right.
  systemd.tmpfiles.rules = [
    "d /docker-volumes/navidrome 0755 root root -"
    "d /docker-volumes/navidrome/data 0755 165536 165536 -"
    "Z /docker-volumes/navidrome/data - 165536 165536 -"
    "d /docker-volumes/navidrome/cache 0755 165536 165536 -"
    "Z /docker-volumes/navidrome/cache - 165536 165536 -"
  ];

  system.stateVersion = "26.05";
}
