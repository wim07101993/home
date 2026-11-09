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
  imports = [ ./mail.nix ];

  services.clamav.updater.enable = true;

  systemd.services.clamav-scan = {
    description = "ClamAV scan";
    wants = [ "clamav-freshclam.service" ];
    after = [ "clamav-freshclam.service" ];
    startAt = "05:00";
    onFailure = [ "clamav-scan-report.service" ];

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

  # clamscan exits 1 when it found something and 2 when it could not finish.
  systemd.services.clamav-scan-report = {
    description = "Mail the ClamAV scan's findings";
    path = [ config.systemd.package "/run/wrappers" ];
    script = ''
      host=${config.networking.hostName}
      status=$(systemctl show clamav-scan.service --property=ExecMainStatus --value)
      if [ "$status" = 1 ]; then
        subject="ClamAV found something on $host"
        body=$(journalctl --unit=clamav-scan.service --invocation=0 --output=cat --grep='FOUND$')
      else
        subject="ClamAV could not finish scanning $host"
        body=$(journalctl --unit=clamav-scan.service --invocation=0 --output=cat --lines=50)
      fi

      sendmail -t <<EOF
      To: status@wvl.app
      Subject: $subject

      $body

      journalctl -u clamav-scan on $host has the whole run.
      EOF
    '';

    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      # To read the scan's findings from the journal.
      SupplementaryGroups = [ "systemd-journal" ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
    };
  };
}
