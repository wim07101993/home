{
  # From `nixos-generate-config --show-hardware-config` on samson, 2026-10-22,
  # minus the `dm-snapshot` it asked for: that was for the Synology LVM
  # leftovers on the nvme, which nothing here mounts.
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ehci_pci"
    "ahci"
    "mpt3sas"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;
}
