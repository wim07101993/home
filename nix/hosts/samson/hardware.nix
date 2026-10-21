{
  # APPROXIMATED, NOT GENERATED. These are the modules a SATA + NVMe + USB box
  # normally needs, not what `nixos-generate-config` observed on this machine.
  # Run it on samson and reconcile before installing: samson is physical
  # hardware, and an initrd missing its storage controller does not boot.
  boot.initrd.availableKernelModules = [
    "ahci"
    "nvme"
    "sd_mod"
    "xhci_pci"
    "ehci_pci"
    "usbhid"
    "usb_storage"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.enableRedistributableFirmware = true;
}
