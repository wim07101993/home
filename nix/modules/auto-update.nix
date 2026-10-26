{ config, pkgs, ... }:

let
  repo = "${config.users.users.wim.home}/source/github/wim07101993/home";

  # Pulls whatever branch the checkout is on and switches to it, cloning it
  # first if it is missing. git runs as wim, who owns the checkout and works in
  # it by hand; as root it would leave root-owned objects behind.
  homeUpdate = pkgs.writeShellApplication {
    name = "home-update";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gitMinimal
      pkgs.util-linux
      config.nix.package
    ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        exec sudo "$0" "$@"
      fi

      as_wim() {
        runuser -u wim -- env HOME=${config.users.users.wim.home} "$@"
      }

      if [ ! -d ${repo}/.git ]; then
        as_wim git clone https://github.com/wim07101993/home ${repo}
      fi
      as_wim git -C ${repo} pull --ff-only

      # Nix refuses a git repository that root does not own (sudo is the
      # exception), so wim builds the system and root only switches to it.
      system=$(as_wim nix --extra-experimental-features "nix-command flakes" \
        build --no-link --print-out-paths \
        "${repo}/nix#nixosConfigurations.${config.networking.hostName}.config.system.build.toplevel")
      nix-env -p /nix/var/nix/profiles/system --set "$system"
      "$system/bin/switch-to-configuration" switch
    '';
  };
in
{
  environment.systemPackages = [ homeUpdate ];

  systemd.services.home-update = {
    description = "Pull the home repo and switch to it";

    # Belgian time, not the hosts' UTC.
    startAt = "*-*-* 04:45:00 Europe/Brussels";

    # The switch this runs may change this very unit. Restarting it then would
    # kill the switch halfway through.
    restartIfChanged = false;
    unitConfig.X-StopOnRemoval = false;

    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = config.nix.envVars // { HOME = "/root"; };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${homeUpdate}/bin/home-update";
    };
  };
}
