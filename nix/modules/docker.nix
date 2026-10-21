{
  virtualisation.docker = {
    enable = true;
    storageDriver = "overlay2";

    daemon.settings = {
      data-root = "/var/lib/docker";
      log-driver = "json-file";

      # Root in a container is uid 165536 on the host, not uid 0, so a breakout
      # lands as nobody. Containers that need the real host -- host networking,
      # devices, files owned by host users -- opt out with `userns_mode = "host"`
      # in tofu. Files under /docker-volumes must be owned by the shifted ids;
      # see ../README.md.
      userns-remap = "dockremap";
    };
  };

  users.users.dockremap = {
    isSystemUser = true;
    group = "dockremap";
    subUidRanges = [{ startUid = 165536; count = 65536; }];
    subGidRanges = [{ startGid = 165536; count = 65536; }];
  };
  users.groups.dockremap = { };

  users.users.wim.extraGroups = [ "docker" ];

  systemd.tmpfiles.rules = [
    "d /docker-volumes 0755 root root -"
  ];
}
