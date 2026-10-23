{
  imports = [
    ./disko.nix
    ../../modules/base.nix
    ../../modules/hetzner.nix
    ../../modules/docker.nix
    ../../modules/tailscale.nix
    ../../modules/clamav.nix
  ];

  networking.hostName = "mindy";

  networking.interfaces.eth0.ipv6.addresses = [{
    address = "2a01:4f8:c012:a6f3::1";
    prefixLength = 64;
  }];

  # The Hetzner volume, by its stable device alias rather than by UUID: the alias
  # is derived from the volume id, which OpenTofu owns
  # (module.hetzner.hcloud_volume.data, id 103225027), so it survives a reinstall
  # while a filesystem UUID would have to be rediscovered.
  #
  # NOT in disko on purpose -- see disko.nix.
  fileSystems."/mnt/rafiki" = {
    device = "/dev/disk/by-id/scsi-0HC_Volume_103225027";
    fsType = "ext4";
    options = [ "discard" "defaults" "nofail" "x-systemd.before=docker.service" ];
  };

  # Service data that lives on rafiki rather than the OS disk; tofu still binds
  # the /docker-volumes paths. `L`, not `L+`: an existing directory there is
  # left alone instead of deleted.
  systemd.tmpfiles.rules = [
    "L /docker-volumes/immich/photos - - - - /mnt/rafiki/photos"
    "L /docker-volumes/filebrowser/files/audio - - - - /mnt/rafiki/audio"
    "L /docker-volumes/filebrowser/files/gezin-officieel - - - - /mnt/rafiki/documents/gezin-officieel"
    "L /docker-volumes/filebrowser/files/gezin-officieel-archive - - - - /mnt/rafiki/documents/gezin-officieel-archive"
    "L /docker-volumes/filebrowser/files/sara - - - - /mnt/rafiki/documents/sara"
    "L /docker-volumes/filebrowser/files/wim - - - - /mnt/rafiki/documents/wim"
  ];

  # audio-archive lives on samson and is served by filebrowser here. x-systemd
  # options keep a boot from hanging when samson is down, which it is whenever
  # the residential line is.
  fileSystems."/docker-volumes/filebrowser/files/audio-archive" = {
    device = "100.71.248.106:/nfs-volumes/audio-archive";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "_netdev"
      "x-systemd.automount"
      "x-systemd.mount-timeout=15"
      "hard"
      "timeo=150"
      "retrans=3"
    ];
  };

  system.stateVersion = "26.05";
}
