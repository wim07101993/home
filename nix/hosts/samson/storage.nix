{ lib, ... }:

let
  # OpenMediaVault's naming, kept rather than tidied: OpenTofu's plex module
  # binds <array>/media into the container by this exact path, so renaming the
  # mountpoint is a tofu change, not a nix one. It is also the last service bind
  # outside /docker-volumes.
  array = "/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300";

  # <name under /export> => subdirectory of the array. Bind mounts, exactly as
  # OMV's fstab had them, so NFS exports a stable path per share rather than the
  # array's internal layout.
  shares = [
    "media"
    "photos"
    "audio"
    "audio-archive"
    "gezin-officieel"
    "gezin-officieel-archive"
    "sara"
    "wim"
    "backups"
  ];
in
{
  fileSystems = lib.mkMerge [
    {
      # The 8.4 TiB RAID1. Three devices, one UUID -- btrfs finds the others
      # itself, so it is mounted by UUID and the members are never named here.
      # They are absent from disko.nix too, which is what stops them being
      # formatted.
      ${array} = {
        device = "/dev/disk/by-uuid/25d0f3ec-68a9-4ce0-891e-0966088e5300";
        fsType = "btrfs";
        options = [ "defaults" "nofail" ];
      };
    }

    (lib.listToAttrs (map
      (name: lib.nameValuePair "/export/${name}" {
        device = "${array}/${name}";
        fsType = "none";
        options = [ "bind" "nofail" ];
        depends = [ array ];
      })
      shares))

    {
      # Attached but not mounted at boot, as today.
      "/mnt/backup-14t" = {
        device = "/dev/disk/by-uuid/fbc74530-17f6-4f65-9e40-f4b2537086ca";
        fsType = "btrfs";
        options = [ "noauto" "noatime" "nofail" ];
      };
    }
  ];

  # Transcribed from OMV's /etc/exports verbatim, fsids included. THE FSIDS ARE
  # LOAD-BEARING: with bind mounts over one filesystem, NFS cannot derive a
  # distinct handle per share, and changing one gives every client a stale
  # handle rather than an error. 100.127.106.121 is mindy; 10.0.0.0/16 is the LAN.
  services.nfs.server = {
    enable = true;
    exports = ''
      /export/media 10.0.0.0/16(fsid=89b65970-76de-4f03-8b66-991b6470c18f,rw,rw,async,no_subtree_check,insecure,no_root_squash) 100.127.106.121(fsid=9af302d7-925c-49a2-a749-ac82b33175ee,ro,insecure,no_root_squash,subtree_check)
      /export/photos 100.127.106.121(fsid=9794169f-7560-4217-a6b4-075592ef7cf7,rw,subtree_check,insecure,no_root_squash)
      /export/audio 100.127.106.121(fsid=8fcf427f-4f12-4417-808f-3fee60d16720,rw,subtree_check,insecure,no_root_squash) 10.0.0.0/16(fsid=016ae8b8-b5b5-4f0c-9e23-a4028de63aee,rw,rw,async,no_subtree_check,insecure,no_root_squash)
      /export/audio-archive 100.127.106.121(fsid=640d5507-9592-4dfe-8709-6d3d0c50ed33,rw,subtree_check,insecure,no_root_squash)
      /export/gezin-officieel 100.127.106.121(fsid=1e942c74-d5b4-48ec-b4a9-65f680b0b86d,rw,subtree_check,insecure,no_root_squash)
      /export/gezin-officieel-archive 100.127.106.121(fsid=e7c1937d-6904-40bb-9dda-b7536917a90d,rw,subtree_check,insecure,no_root_squash)
      /export/sara 100.127.106.121(fsid=17d37c5a-1fb7-4b1d-9c4a-47d557bea30b,rw,subtree_check,insecure,no_root_squash)
      /export/wim 100.127.106.121(fsid=01da8857-81a1-4614-976d-53c4f21e41ec,rw,subtree_check,insecure,no_root_squash)
      /export/backups 100.127.106.121(fsid=be8823c8-e321-466c-afbd-dd34b6f672b6,ro,insecure,no_root_squash,subtree_check)
      /export 10.0.0.0/16(ro,fsid=0,root_squash,subtree_check,insecure)
      /export 100.127.106.121(ro,fsid=0,root_squash,subtree_check,insecure)
    '';
  };

  # Clients mount with nfsvers=3, so rpcbind and the v3 helpers have to be up.
  services.rpcbind.enable = true;

  networking.firewall.allowedTCPPorts = [ 111 2049 ];
  networking.firewall.allowedUDPPorts = [ 111 2049 ];

  # OMV ran smartmontools; the disks are old enough that it matters.
  services.smartd = {
    enable = true;
    autodetect = true;
  };
}
