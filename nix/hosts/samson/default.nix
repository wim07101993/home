{
  imports = [
    ./disko.nix
    ./hardware.nix
    ./storage.nix
    ../../modules/base.nix
    ../../modules/docker.nix
    ../../modules/tailscale.nix
  ];

  networking.hostName = "samson";

  # Physical host on the LAN: DHCP on the onboard NIC, no static addressing.
  networking.useDHCP = false;
  networking.interfaces.eno1.useDHCP = true;

  # Samba is NOT configured here. OMV shipped smb.conf with a [global] section
  # and no shares at all, so nothing was being served over SMB and there is
  # nothing to port. NFS was doing all of it.

  system.stateVersion = "26.05";
}
