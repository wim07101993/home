{ pkgs, ... }:

{
  imports = [
    ./disko.nix
    ./hardware.nix
    ../../modules/base.nix
    ../../modules/auto-update.nix
    ../../modules/docker.nix
    ../../modules/tailscale.nix
    ../../modules/clamav.nix
  ];

  networking.hostName = "plop";

  networking.useDHCP = false;
  networking.interfaces.eno1.useDHCP = true;

  # mDNS, for the Matter server: it runs with host networking, so the answers
  # to its device discovery arrive through this firewall, sent to the multicast
  # address rather than as replies the firewall can match to a query.
  networking.firewall.interfaces.eno1.allowedUDPPorts = [ 5353 ];

  # Home Assistant talks to devices on the LAN. See docker.nix.
  homelab.containers.mayReachLan = true;

  # AdGuard Home, OpenTofu's adguard-home module, is the resolver the router
  # hands out, plop included. See docker.nix.
  homelab.containers.mayReachPublishedDns = true;

  # The Zigbee/Thread radio: a Nabu Casa SkyConnect on the CP210x UART bridge.
  # OpenTofu's home-assistant module passes /dev/ttyUSB0 into the container by
  # that literal path, so the symlink below is a safety net rather than the thing
  # in use -- ttyUSB0 is allocated in probe order and only happens to be stable
  # because this is the one USB serial device on the machine. Pointing tofu at
  # /dev/zigbee instead is the real fix, and it is a tofu change.
  #
  # Owned by 165536 because that is root inside Home Assistant's remapped user
  # namespace; a root-owned node shows up there as nobody and does not open.
  # chown rather than OWNER=, which only takes a user name and no user has that
  # uid.
  services.udev.extraRules = ''
    SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", SYMLINK+="zigbee", RUN+="${pkgs.coreutils}/bin/chown 165536 $devnode"
  '';

  # Ownership of the volumes OpenTofu's home-assistant and adguard-home modules
  # mount. `Z` re-owns
  # everything below the path on every boot and rebuild, so a restore from a
  # backup taken anywhere comes out right.
  #
  # home-assistant runs remapped: its root is 165536 on this host.
  # matterjs-server runs with userns_mode = "host", as the matter account below.
  systemd.tmpfiles.rules = [
    "d /docker-volumes/homeassistant 0755 root root -"
    "d /docker-volumes/homeassistant/config 0755 165536 165536 -"
    "Z /docker-volumes/homeassistant/config - 165536 165536 -"
    "d /docker-volumes/homeassistant/matterjs-server 0755 matter matter -"
    "Z /docker-volumes/homeassistant/matterjs-server - matter matter -"

    # adguard-home runs remapped too, as 65532: 231068 on this host. Without
    # CAP_DAC_OVERRIDE, so it must own what it writes.
    "d /docker-volumes/adguard-home 0755 root root -"
    "d /docker-volumes/adguard-home/conf 0700 231068 231068 -"
    "Z /docker-volumes/adguard-home/conf - 231068 231068 -"
    "d /docker-volumes/adguard-home/work 0700 231068 231068 -"
    "Z /docker-volumes/adguard-home/work - 231068 231068 -"
  ];

  # tofu's matterjs-server runs as this account instead of the image's uid
  # 1000, which is wim here.
  users.users.matter = {
    isSystemUser = true;
    uid = 950;
    group = "matter";
  };
  users.groups.matter.gid = 950;

  system.stateVersion = "26.05";
}
