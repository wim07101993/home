{ pkgs, ... }:

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

  # plex runs with host networking, so its ports are the host's and the firewall
  # sees them. 32400 is the server itself, which the router also forwards for
  # remote access (manual port mapping); 32410-32414/udp is LAN discovery (GDM).
  # DLNA is off in plex, so 1900/udp and 32469 stay closed.
  networking.firewall.allowedTCPPorts = [ 32400 ];
  networking.firewall.allowedUDPPorts = [ 32410 32412 32413 32414 ];

  # tofu's ftp container, also on host networking: 21 for control and a fixed
  # passive range for data (the module's passive_ports).
  networking.firewall.interfaces.eno1.allowedTCPPorts = [ 21 ];
  networking.firewall.interfaces.eno1.allowedTCPPortRanges = [{ from = 21000; to = 21010; }];

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

  # The server end of tux's Unison profiles (hosts/tux/unison). Without the GUI,
  # which would pull GTK onto a server.
  environment.systemPackages = [ (pkgs.unison.override { enableX11 = false; }) ];

  system.stateVersion = "26.05";
}
