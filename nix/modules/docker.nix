{ config, lib, ... }:

let
  cfg = config.homelab.containers;
in
{
  options.homelab.containers = {
    reachableOnTailnet = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          address = lib.mkOption { type = lib.types.str; };
          port = lib.mkOption { type = lib.types.port; };
        };
      });
      default = [ ];
      description = "TCP destinations on the tailnet that this host's containers may connect to. The rest of the tailnet is closed to them.";
    };

    mayReachLan = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this host's containers may connect to 10.0.0.0/8. DNS there is allowed either way.";
    };
  };

  config = {
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

    # Docker keeps its networks apart from each other, but not from the host: a
    # container reaches every published port through one of the host's
    # addresses, and the tailnet as the host itself. These rules close both, so
    # a container reaches only what shares a network with it, and the internet.
    #
    # In DOCKER-USER, which Docker jumps to first and otherwise leaves alone.
    # Created here in case the firewall starts before Docker, and flushed so a
    # reload does not stack copies.
    networking.firewall.extraCommands = ''
      iptables -w -N DOCKER-USER 2>/dev/null || true
      iptables -w -F DOCKER-USER
      iptables -w -N from-containers 2>/dev/null || iptables -w -F from-containers

      iptables -w -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
      iptables -w -A DOCKER-USER -i docker0 -j from-containers
      iptables -w -A DOCKER-USER -i br-+ -j from-containers

      # Published ports, reached through this host's addresses. Except traefik's,
      # which the internet reaches anyway: gatus checks bumba's own sites there.
      iptables -w -A from-containers -p tcp -m conntrack --ctstate DNAT --ctorigdstport 80 -j RETURN
      iptables -w -A from-containers -p tcp -m conntrack --ctstate DNAT --ctorigdstport 443 -j RETURN
      iptables -w -A from-containers -m conntrack --ctstate DNAT -j DROP

      # Cloud metadata, which hands the server's user data to whoever asks.
      iptables -w -A from-containers -d 169.254.169.254 -j DROP

      # The tailnet: its DNS, ping, and what the host allows.
      iptables -w -A from-containers -o tailscale0 -d 100.100.100.100 -p udp --dport 53 -j RETURN
      iptables -w -A from-containers -o tailscale0 -d 100.100.100.100 -p tcp --dport 53 -j RETURN
      iptables -w -A from-containers -o tailscale0 -p icmp --icmp-type echo-request -j RETURN
      ${lib.concatMapStrings (destination: ''
        iptables -w -A from-containers -o tailscale0 -d ${destination.address} -p tcp --dport ${toString destination.port} -j RETURN
      '') cfg.reachableOnTailnet}
      iptables -w -A from-containers -o tailscale0 -j DROP
    '' + lib.optionalString (!cfg.mayReachLan) ''

      # The LAN, apart from DNS.
      iptables -w -A from-containers -d 10.0.0.0/8 -p udp --dport 53 -j RETURN
      iptables -w -A from-containers -d 10.0.0.0/8 -p tcp --dport 53 -j RETURN
      iptables -w -A from-containers -d 10.0.0.0/8 -j DROP
    '';
    networking.firewall.extraStopCommands = ''
      iptables -w -F DOCKER-USER 2>/dev/null || true
      iptables -w -F from-containers 2>/dev/null || true
      iptables -w -X from-containers 2>/dev/null || true
    '';

    # The other half of the traefik exception above. Docker does not DNAT a
    # published port for traffic from the network it is published on, so gatus,
    # which shares traefik-gatus with traefik, reaches bumba's sites through
    # docker-proxy on INPUT instead, and is refused there without this.
    networking.firewall.interfaces."br-+".allowedTCPPorts = [ 80 443 ];
  };
}
