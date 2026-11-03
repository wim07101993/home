{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # audio / light
    audacity
    musescore
    qlcplus
    spotdl
    spotify
    yt-dlp
    (callPackage ./wing-edit/package.nix { })
    # sync
    unison
  ];

  systemd.tmpfiles.rules = [
    "d /home/wim/drive 0755 wim users -"
    "d /home/wim/.unison 0700 wim users -"
    "L+ /home/wim/.unison/common - - - - ${./unison/common}"
    "L+ /home/wim/.unison/audio.prf - - - - ${./unison/audio.prf}"
    "L+ /home/wim/.unison/archive.prf - - - - ${./unison/audio-archive.prf}"
  ];

  # QLC+'s rules for USB DMX interfaces. Upstream opens them to everyone (0666),
  # including every plain FTDI serial adapter (0403:6001).
  services.udev.packages = [ pkgs.qlcplus ];

  # Linux Show Player comes from Flathub; services.flatpak is enabled in
  # ../laptop.nix.
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
}
