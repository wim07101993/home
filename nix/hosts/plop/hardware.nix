{
  # APPROXIMATED, NOT GENERATED -- run `nixos-generate-config` on plop and
  # reconcile. An Ivy Bridge OptiPlex is about as standard as SATA gets, but
  # this is physical hardware and a wrong initrd does not boot.
  boot.initrd.availableKernelModules = [
    "ahci"
    "sd_mod"
    "xhci_pci"
    "ehci_pci"
    "usbhid"
    "usb_storage"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.enableRedistributableFirmware = true;
}
