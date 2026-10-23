{ modulesPath, ... }:

{
  # The virtio drivers the initrd needs to find the root disk. Nothing else
  # brings them in: these hosts have no generated hardware configuration.
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  services.qemuGuest.enable = true;

  # Every Hetzner Cloud server here boots legacy BIOS -- verified by the absence
  # of /sys/firmware/efi on bumba and mindy. The images ship an ESP as well, so
  # a mounted /boot/efi is not evidence of EFI boot. Hetzner fixes the mode at
  # creation and keeps it through a resize.
  # The hosts and this module configure eth0, the name Debian used. NixOS would
  # otherwise rename the NIC to enp1s0.
  networking.usePredictableInterfaceNames = false;
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
