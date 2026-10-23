{ config, lib, pkgs, ... }:

let
  # The bot from the October 2026 Plex compromise on samson (Mirai/Gafgyt, per
  # VirusTotal), dropped as both /var/tmp/.spid and /var/tmp/kworker, and its
  # launcher /var/tmp/kworker.sh, by SHA-256 and size. They only match those
  # exact files, so they catch the same campaign coming back, not the next one;
  # that is what freshclam's signatures are for.
  incidentSignatures = pkgs.writeText "samson-plex-2026-10.hsb" ''
    0a33219aac70bd58053e542e99cfae1292d85fa349c883ce9f760bda531ae70d:412608:Samson-Plex-2026-10.Bot
    478cd2398da46773e08b733e1944b0655149b93fde34701f4c253979b076590f:235:Samson-Plex-2026-10.Launcher
  '';
in
{
  # freshclam, hourly, into /var/lib/clamav.
  services.clamav.updater.enable = true;

  # A nightly clamscan instead of the module's own scanner
  # (services.clamav.scanner). That one needs clamd, which keeps the signatures
  # in memory around the clock -- about 1 GB, twice that while it reloads after
  # an update -- for a scan that runs once a day. And clamdscan counts every
  # socket and device node it walks past as an error; docker's layers are full
  # of whiteouts, which are character devices, so it would exit 2 every night.
  # clamscan skips those silently: exit 1 means it found something, 2 that the
  # scan itself broke.
  systemd.services.clamav-scan = {
    description = "ClamAV scan";
    wants = [ "clamav-freshclam.service" ];
    after = [ "clamav-freshclam.service" ];
    startAt = "04:00";

    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.escapeShellArgs [
        "${config.services.clamav.package}/bin/clamscan"
        # nixpkgs' clamav would look for signatures in its own store path.
        "--database=/var/lib/clamav"
        "--database=${incidentSignatures}"
        "--tempdir=/var/cache/clamav-scan"
        "--recursive"
        "--infected"
        # Not into other mounts: running containers' overlay views (their files
        # are in the layers under /var/lib/docker already), samson's rpc_pipefs,
        # mindy's NFS automount of samson's audio archive.
        "--cross-fs=no"
        # The layers sit five directories below /var/lib
        # (docker/165536.165536/overlay2/<id>/diff), which leaves the default of
        # 15 only ten inside an image. node_modules goes deeper, and clamscan
        # skips whatever is past the limit without saying so.
        "--max-dir-recursion=40"
        # The signatures themselves, which freshclam may be replacing mid-scan.
        "--exclude-dir=^/var/lib/clamav/"
        "/home"
        "/root"
        "/etc"
        "/tmp"
        "/var/tmp"
        "/dev/shm"
        "/var/lib" # docker's layers and volumes
        "/docker-volumes"
      ];
      Nice = 19;
      IOSchedulingClass = "idle";

      # The parsers run over whatever a compromised container left behind, so
      # not as root: read access to everything, write access only to the temp
      # directory, no network. The module's scanner gets the same separation by
      # having a root clamdscan pass open files to an unprivileged clamd.
      #
      # clamscan checks every file with access(), and access() ignores a
      # non-root process's capabilities unless no-setuid-fixup is set. Without
      # it, every file clamav could not read on its own is "Access denied" and
      # the scan exits 2.
      User = "clamav";
      AmbientCapabilities = "CAP_DAC_READ_SEARCH";
      CapabilityBoundingSet = "CAP_DAC_READ_SEARCH";
      SecureBits = "no-setuid-fixup";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      CacheDirectory = "clamav-scan";
      PrivateNetwork = true;
    };
  };
}
