{
  services.qemuGuest.enable = true;

  # Every Hetzner Cloud server here boots legacy BIOS -- verified by the absence
  # of /sys/firmware/efi on bumba and mindy. The images ship an ESP as well, so
  # a mounted /boot/efi is not evidence of EFI boot. Hetzner fixes the mode at
  # creation, and neither cpx11 nor these volumes can be reordered.
  networking.useDHCP = false;
  networking.interfaces.eth0.useDHCP = true;

  # IPv6 is routed to the server rather than offered over DHCPv6, and the
  # gateway is link-local, so the default route is onlink. The address itself is
  # per-host.
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = "eth0";
  };
}
