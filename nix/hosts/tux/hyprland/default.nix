{ pkgs, ... }:

# A Hyprland session next to Plasma, with Omarchy's keybindings and look and a
# Quickshell bar and launcher in place of Omarchy's own shell.
#
# Plasma is left alone: the configs below sit in /etc/xdg, where only the Hypr
# tools look, and everything the session needs (bar, idle, night light, polkit
# agent) is started from hyprland.lua rather than as a service.
#
# A ~/.config/hypr/hyprland.lua or hyprland.conf wins over these. Hyprland
# writes one on a first login without a config, so delete it if it exists.
{
  programs.hyprland.enable = true;
  # Also adds hyprlock's PAM service.
  programs.hyprlock.enable = true;

  environment.etc = {
    "xdg/hypr/hyprland.lua".source = pkgs.substitute {
      src = ./hyprland.lua;
      substitutions = [ "--replace-fail" "@polkitAgent@" "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent" ];
    };
    "xdg/hypr/desktop".source = ./desktop;
    "xdg/hypr/hypridle.conf".source = ./hypridle.conf;
    "xdg/hypr/hyprlock.conf".source = ./hyprlock.conf;
    "xdg/quickshell/desktop".source = ./quickshell;
    "alacritty/alacritty.toml".source = ./alacritty.toml;
  };

  environment.systemPackages = with pkgs; [
    quickshell
    hypridle
    hyprsunset
    hyprshot
    hyprpicker
    alacritty
    # For web apps: Firefox has no window-per-site mode.
    chromium
    # The terminal UIs behind the bar's network, Bluetooth and volume icons.
    networkmanager
    bluetui
    wiremix
    brightnessctl
    playerctl
    wl-clipboard
    libnotify

    (writeShellApplication {
      name = "system-update";
      runtimeInputs = [ git ];
      text = builtins.readFile ./system-update.sh;
    })
    (writeShellApplication {
      name = "webapp-install";
      runtimeInputs = [ curl libnotify ];
      text = builtins.readFile ./webapp-install.sh;
    })
    (writeShellApplication {
      name = "webapp-remove";
      runtimeInputs = [ libnotify ];
      text = builtins.readFile ./webapp-remove.sh;
    })
  ];

  fonts.packages = [ pkgs.nerd-fonts.caskaydia-mono ];
}
