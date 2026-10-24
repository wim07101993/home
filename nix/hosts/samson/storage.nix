{ lib, pkgs, ... }:

let
  array = "/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300";
in
{
  fileSystems = lib.mkMerge [
    {
      ${array} = {
        device = "/dev/disk/by-uuid/25d0f3ec-68a9-4ce0-891e-0966088e5300";
        fsType = "btrfs";
        options = [ "defaults" "nofail" "x-systemd.before=docker.service" "x-systemd.required-by=docker.service" ];
      };
    }

    {
      "/nfs-volumes/audio-archive" = {
        device = "${array}/audio-archive";
        fsType = "none";
        options = [ "bind" "nofail" ];
        depends = [ array ];
      };
    }

    {
      # Attached but not mounted at boot, as today.
      "/mnt/backup-14t" = {
        device = "/dev/disk/by-uuid/fbc74530-17f6-4f65-9e40-f4b2537086ca";
        fsType = "btrfs";
        options = [ "noauto" "noatime" "nofail" ];
      };
    }
  ];

  # One export, one client: mindy (100.127.106.121), whose filebrowser serves
  # audio-archive. Nothing on the LAN mounts anything, so there is no LAN export
  # and no explicit NFSv4 root (fsid=0): nfsd builds one from the exports, so the
  # path is /nfs-volumes/audio-archive under v4 too. mindy comes in over
  # tailscale0, which the firewall trusts, so no NFS port is opened.
  services.nfs.server = {
    enable = true;
    exports = ''
      /nfs-volumes/audio-archive 100.127.106.121(fsid=640d5507-9592-4dfe-8709-6d3d0c50ed33,rw,subtree_check)
    '';
  };

  services.nfs.settings.nfsd.vers3 = false;

  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ array ];
  };

  # Snapshots of every share, sent to the 14 TB disk. Ported from OMV's
  # /etc/btrbk/btrbk.conf. Run by hand, as it was -- no timer -- after mounting
  # /mnt/backup-14t: `sudo btrbk run`.
  services.btrbk.instances.btrbk = {
    onCalendar = null;
    settings = {
      transaction_log = "/var/log/btrbk.log";
      timestamp_format = "long";
      stream_buffer = "256m";
      snapshot_dir = "_btrbk_snap";
      snapshot_preserve_min = "18m";
      snapshot_preserve = "36m";
      target_preserve_min = "latest";
      target_preserve = "7d 24m 10y";
      volume.${array} = {
        target = "/mnt/backup-14t";
        subvolume = lib.genAttrs [ "media" "audio-archive" "backups" ] (_: { });
      };
    };
  };

  environment.systemPackages = [ pkgs.mbuffer pkgs.smartmontools ];

  services.smartd = {
    enable = true;
    autodetect = true;
    notifications.mail = {
      enable = true;
      sender = "samson@mail.wvl.app";
      recipient = "wim@wvl.app";
    };
  };
}
