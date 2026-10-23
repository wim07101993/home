{
  # ONLY the OS disk. The 100 GB Hetzner volume (rafiki) is deliberately absent
  # from disko and declared as a plain fileSystems entry in default.nix, so that
  # nothing here can format it. disko wipes what it is given.
  disko.devices.disk.main = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_114517127";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02";
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
