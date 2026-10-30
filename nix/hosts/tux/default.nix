{ pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ../../modules/laptop.nix
    ../../modules/hyprland
    ../../modules/live-shows
  ];

  networking.hostName = "tux";

  # A TUXEDO Pulse 15 Gen1. nixos-hardware only has the Gen2, and the parts of
  # it that apply to a Gen1 (AMD graphics, power profiles, SSD trim) Plasma and
  # NixOS already enable.
  hardware.tuxedo-drivers.enable = true;

  # Face recognition with the IR camera, as an alternative to the password
  # rather than a second factor. Not for changing the password itself.
  services.howdy = {
    enable = true;
    control = "sufficient";
    settings.video.device_path = "/dev/video2";
  };
  security.pam.services.passwd.howdy.enable = false;

  users.users.wim.extraGroups = [ "kvm" ];

  # Flutter's Android builds run tools Gradle downloads (aapt2 and the like),
  # which are linked for a regular distro's /lib.
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    # system
    opentofu
    # dev
    android-studio
    flutter
    git
    github-copilot-cli
    go
    jetbrains.goland
    neovim
    # secret
    bitwarden-cli
    yubioath-flutter
    # internet
    filezilla
    qbittorrent
    tor-browser
  ];

  # Yubico Authenticator reaches the YubiKey as a smart card.
  services.pcscd.enable = true;

  system.stateVersion = "26.05";
}
