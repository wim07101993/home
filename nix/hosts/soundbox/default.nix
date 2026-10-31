{ lib, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ../../modules/laptop.nix
    ../../modules/hyprland
    ../../modules/live-shows
    ./technician.nix
  ];

  networking.hostName = "soundbox";

  services.fprintd.enable = true;
  security.pam.services.login.fprintAuth = false;
  security.pam.services.hyprlock.fprintAuth = false;
  environment.etc."xdg/hypr/hyprlock.conf".source = lib.mkForce (pkgs.writeText "hyprlock.conf" (
    lib.replaceStrings [ "Password, or Enter for your face" ] [ "Password, or your finger" ]
      (builtins.readFile ../../modules/hyprland/hyprlock.conf)
    + ''

      auth {
          fingerprint:enabled = true
      }
    ''
  ));

  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
    IdleAction = "ignore";
  };

  environment.etc."xdg/hypr/hypridle.conf".source = lib.mkForce ./hypridle.conf;

  environment.etc."xdg/kscreenlockerrc".text = ''
    [Daemon]
    Autolock=false
    LockOnResume=false
  '';
  environment.etc."xdg/powerdevilrc".text = lib.concatMapStrings
    (profile: ''
      [${profile}][Display]
      DimDisplayWhenIdle=false
      TurnOffDisplayWhenIdle=false

      [${profile}][SuspendAndShutdown]
      AutoSuspendAction=0
      LidAction=0

    '')
    [ "AC" "Battery" "LowBattery" ];

  system.stateVersion = "26.05";
}
