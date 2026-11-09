{ config, ... }:

{
  # Through tofu's smtp-relay container on this host, which only listens on
  # 127.0.0.1 and holds the host's own Mailgun credential.
  programs.msmtp = {
    enable = true;
    setSendmail = true;
    accounts.default = {
      host = "127.0.0.1";
      port = 2525;
      from = "${config.networking.hostName}@mail.wvl.app";
      auth = false;
      tls = false;
    };
  };
}
