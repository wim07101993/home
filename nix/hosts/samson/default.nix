{ pkgs, ... }:

{
  imports = [
    ./disko.nix
    ./hardware.nix
    ./storage.nix
    ../../modules/base.nix
    ../../modules/auto-update.nix
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

  # navidrome runs remapped as 1000:1000: 166536 on this host. `Z` re-owns its
  # volumes on every boot and rebuild, so a restore comes out right.
  systemd.tmpfiles.rules = [
    "d /docker-volumes/navidrome 0755 root root -"
    "d /docker-volumes/navidrome/data 0755 166536 166536 -"
    "Z /docker-volumes/navidrome/data - 166536 166536 -"
    "d /docker-volumes/navidrome/cache 0755 166536 166536 -"
    "Z /docker-volumes/navidrome/cache - 166536 166536 -"
  ];

  # Who may write the media library: tofu's ftp logs its users in as 951, and
  # wim. plex and navidrome only read it, as "other". ftp also writes the audio
  # archive, through an ACL; its group stays users.
  users.groups.media.gid = 951;
  users.users.ftp-media = {
    isSystemUser = true;
    uid = 951;
    group = "media";
  };
  users.users.wim.extraGroups = [ "media" ];

  # Keeps the library in that group and group-writable, wim's trash aside. New
  # entries inherit the group from the setgid folders; this catches the rest.
  #
  # The audio archive gets media as an extra ACL entry instead. -n keeps the
  # mask at the group bits, so media can do what users can and no more; the
  # default entries on the folders carry it to new entries.
  systemd.services.media-permissions =
    let
      media = "/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300/media";
      audioArchive = "/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300/audio-archive";
    in
    {
      description = "Keep the media library and the audio archive writable by the media group";
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = [ media audioArchive ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.findutils pkgs.coreutils pkgs.acl ];
      script = ''
        find ${media} -xdev -path '*/.Trash-*' -prune -o ! -group media -exec chgrp -h media {} +
        find ${media} -xdev -path '*/.Trash-*' -prune -o ! -type l ! -perm -g+w -exec chmod g+w {} +
        setfacl -R -P -n -m g:media:rwX ${audioArchive}
        find ${audioArchive} -xdev -type d -exec setfacl -n -m d:g:media:rwx {} +
      '';
    };

  # The server end of tux's Unison profiles (hosts/tux/unison). Without the GUI,
  # which would pull GTK onto a server.
  environment.systemPackages = [ (pkgs.unison.override { enableX11 = false; }) ];

  system.stateVersion = "26.05";
}
