{
  # A copy of bumba's layout on purpose. If the rehearsal VM turns out to boot
  # UEFI where bumba boots BIOS, this is the file that has to diverge -- and that
  # divergence is itself the finding, because it means the rehearsal stops
  # covering bumba's bootloader.
  disko.devices.disk.main = {
    # The only host that may name a bare letter: the VM is created with one
    # disk and destroyed after. Every other host uses by-id -- see
    # ../samson/disko.nix for what that rule is protecting against.
    device = "/dev/sda";
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
