{ pkgs, nixpkgs-unstable, ... }:

{
  imports = [
    ./hardware.nix
    ../../modules/tailscale.nix
    "${nixpkgs-unstable}/nixos/modules/services/networking/nordvpn.nix"
  ];

  # NordVPN reached nixpkgs after 26.05 branched off. Once a release has it
  # (26.11 should), drop this, the import above and the flake's
  # nixpkgs-unstable input.
  nixpkgs.overlays = [
    (final: prev: {
      nordvpn = (import nixpkgs-unstable { inherit (prev.stdenv.hostPlatform) system; }).nordvpn;
    })
  ];
  services.nordvpn.enable = true;

  networking.hostName = "laptop";
  networking.networkmanager.enable = true;

  # A TUXEDO Pulse 15 Gen1. nixos-hardware only has the Gen2, and the parts of
  # it that apply to a Gen1 (AMD graphics, power profiles, SSD trim) Plasma and
  # NixOS already enable.
  hardware.tuxedo-drivers.enable = true;
  hardware.bluetooth.enable = true;

  # Face recognition with the IR camera, as an alternative to the password
  # rather than a second factor. Not for changing the password itself.
  services.howdy = {
    enable = true;
    control = "sufficient";
    settings.video.device_path = "/dev/video2";
  };
  security.pam.services.passwd.howdy.enable = false;

  # What Calamares sets up on UEFI. Check these against the laptop's
  # /etc/nixos/configuration.nix before the first switch: it also holds the
  # timezone, locale and keyboard layout picked in the installer, and the LUKS
  # devices of an encrypted install.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  time.timeZone = "Europe/Brussels";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.printing.enable = true;
  programs.firefox.enable = true;

  users.users.wim = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "kvm" "nordvpn" ];
  };

  nixpkgs.config.allowUnfree = true;

  # Flutter's Android builds run tools Gradle downloads (aapt2 and the like),
  # which are linked for a regular distro's /lib.
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    git
    neovim
    tldr
    opentofu
    go
    flutter
    jetbrains.goland
    android-studio
    bitwarden-cli
    qlcplus
    (callPackage ./wing-edit/package.nix { })
  ];

  # QLC+'s rules for USB DMX interfaces. Upstream opens them to everyone (0666),
  # including every plain FTDI serial adapter (0403:6001).
  services.udev.packages = [ pkgs.qlcplus ];

  services.flatpak.enable = true;

  systemd.services.install-linux-show-player = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "!/var/lib/flatpak/app/org.linuxshowplayer.LinuxShowPlayer";
    path = [ pkgs.flatpak ];
    serviceConfig.Type = "oneshot";
    script = ''
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      flatpak install --noninteractive flathub org.linuxshowplayer.LinuxShowPlayer
    '';
  };

  system.stateVersion = "26.05";
}
