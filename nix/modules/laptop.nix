{ lib, pkgs, nixpkgs-unstable, ... }:

# What wim's laptops share: Plasma, audio, VPNs and the everyday tools. The
# hardware, and what the laptop is for, stay with the host.
{
  imports = [
    ./tailscale.nix
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
  # The module brings a manual chapter that 26.05's list of manual pages does
  # not know, which fails the manual's build.
  documentation.nixos.checkRedirects = false;

  networking.networkmanager.enable = true;

  # Lets wim run `tailscale up`, `set` and the like without sudo.
  services.tailscale.extraSetFlags = [ "--operator=wim" ];

  hardware.bluetooth.enable = true;

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

  security.pam.services.login.kwallet.enable = lib.mkForce false;
  security.pam.services.kde.kwallet.enable = lib.mkForce false;
  environment.etc."xdg/kwalletrc".text = ''
    [Wallet][$i]
    Enabled=false
  '';

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
    extraGroups = [ "wheel" "networkmanager" "nordvpn" ];
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    # system
    btop
    tldr
  ];

  services.flatpak.enable = true;
}
