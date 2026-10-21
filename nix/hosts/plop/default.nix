{
  imports = [
    ./disko.nix
    ./hardware.nix
    ../../modules/base.nix
    ../../modules/docker.nix
    ../../modules/tailscale.nix
  ];

  networking.hostName = "plop";

  networking.useDHCP = false;
  networking.interfaces.eno1.useDHCP = true;

  # The Zigbee/Thread radio: a Nabu Casa SkyConnect on the CP210x UART bridge.
  # OpenTofu's home-assistant module passes /dev/ttyUSB0 into the container by
  # that literal path, so the symlink below is a safety net rather than the thing
  # in use -- ttyUSB0 is allocated in probe order and only happens to be stable
  # because this is the one USB serial device on the machine. Pointing tofu at
  # /dev/zigbee instead is the real fix, and it is a tofu change.
  services.udev.extraRules = ''
    SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", SYMLINK+="zigbee"
  '';

  system.stateVersion = "26.05";
}
