# Rspamd runs as a Sendmail milter for Stalwart (see ./stalwart.nix): the
# rspamd_proxy worker speaks milter natively and self-scans. No redis (bayes/
# fuzzy storage) and no DKIM signing yet — the milter pipeline is enough for
# the initial LAN-only setup.
_:

{
  services.rspamd = {
    enable = true;
    workers = {
      # `workers` replaces the module default set, so the base workers are
      # repeated here.
      normal = { };
      controller = { };
      rspamd_proxy = {
        bindSockets = [ "127.0.0.1:11332" ];
        extraConfig = ''
          milter = true;
          upstream "local" {
            default = yes;
            self_scan = yes;
          }
        '';
      };
    };
  };
}
