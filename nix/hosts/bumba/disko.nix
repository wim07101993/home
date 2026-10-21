{
  # bumba boots LEGACY BIOS, not UEFI: /sys/firmware/efi is absent on the live
  # host. The Debian cloud image it was built from ships both a bios_grub
  # partition and an ESP, so the mounted /boot/efi there is a red herring.
  # Hetzner fixes the firmware mode at server creation and cpx11 cannot be
  # reordered, so an EFI-only layout here would install cleanly and then fail to
  # boot, recoverable only from the rescue console.
  disko.devices.disk.main = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_100235188";
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
