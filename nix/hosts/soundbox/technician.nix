{ lib, ... }:

let
  rules = [
    { tool = "iptables"; rule = "OUTPUT -o tailscale0 -d 100.100.100.100 -p udp --dport 53 -m owner --uid-owner tech -j ACCEPT"; }
    { tool = "iptables"; rule = "OUTPUT -o tailscale0 -d 100.100.100.100 -p tcp --dport 53 -m owner --uid-owner tech -j ACCEPT"; }
    { tool = "iptables"; rule = "OUTPUT -o tailscale0 -m owner --uid-owner tech -j REJECT"; }
    { tool = "ip6tables"; rule = "OUTPUT -o tailscale0 -m owner --uid-owner tech -j REJECT"; }
  ];
  deleteRules = lib.concatMapStrings (r: "${r.tool} -D ${r.rule} 2>/dev/null || true\n") rules;
in
{
  users.users.tech = {
    isNormalUser = true;
    description = "Technician";
  };

  fileSystems."/srv/audio" = {
    device = "/home/wim/drive/audio";
    fsType = "none";
    options = [ "bind" "ro" "nofail" "x-systemd.automount" ];
  };
  systemd.tmpfiles.rules = [
    "d /home/wim/drive/audio 0755 wim users -"
    "L+ /home/tech/audio - - - - /srv/audio"
  ];

  networking.firewall.extraCommands = deleteRules + lib.concatMapStrings (r: "${r.tool} -A ${r.rule}\n") rules;
  networking.firewall.extraStopCommands = deleteRules;
}
