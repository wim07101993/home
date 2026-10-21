{
  # ONLY /dev/sda, the 119 GB OS disk. The 8.4 TiB btrfs RAID1 (sdc/sdd/sde),
  # the two 4.5 TiB ext4 disks, the 14 TB backup disk and the Synology md/LVM
  # leftovers on the nvme are ALL absent from this file on purpose. disko
  # formats every device it is given, and those three devices hold the only copy
  # of the media library.
  disko.devices.disk.os = {
    # BY-ID, NOT /dev/sda. On 2026-10-06 /dev/sda on this machine was devid 3
    # of the RAID1 (serial ZA1EGG4T) and the OS SSD had become /dev/sde --
    # the letters had shuffled since 2026-10-03. A disko run naming /dev/sda
    # would have formatted an array member.
    device = "/dev/disk/by-id/ata-Intenso_SSD_TD25100005785";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02";
        };
        swap = {
          size = "6G";
          content = {
            type = "swap";
            discardPolicy = "both";
          };
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
