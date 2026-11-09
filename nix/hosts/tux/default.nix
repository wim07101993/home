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
    btop
    opentofu
    tldr
    unison
    # secret
    bitwarden-cli
    yubioath-flutter
    # dev
    android-studio
    flutter
    git
    github-copilot-cli
    go
    jetbrains.goland
    neovim
    # audio / light
    audacity
    musescore
    qlcplus
    spotdl
    spotify
    yt-dlp
    (callPackage ./wing-edit/package.nix { })
    # internet
    filezilla
    qbittorrent
    tor-browser
  ];

  systemd.tmpfiles.rules = [
    "d /home/wim/drive 0755 wim users -"
    "d /home/wim/.unison 0700 wim users -"
    "L+ /home/wim/.unison/common - - - - ${./unison/common}"
    "L+ /home/wim/.unison/audio.prf - - - - ${./unison/audio.prf}"
    "L+ /home/wim/.unison/archive.prf - - - - ${./unison/audio-archive.prf}"
  ];

  # Yubico Authenticator reaches the YubiKey as a smart card.
  services.pcscd.enable = true;

  system.stateVersion = "26.05";
}
