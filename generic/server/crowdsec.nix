# CrowdSec watches stalwart's journal for auth failures and bans via the
# nftables bouncer. Stalwart has no native CrowdSec integration; its built-in
# auto-ban (server.auto-ban) stays on as a second layer.
#
# The parser below is a defensive scaffold: the grok matches nothing yet, so
# no stalwart event (and therefore no ban) is produced until a real pattern
# from captured journal samples replaces the placeholder — see
# docs/debug/mail.md for the cscli explain loop.
_:

{
  services.crowdsec = {
    enable = true;

    # Local API for the firewall bouncer. 8080 is traefik's metrics listener
    # on melon, so the LAPI moves to 8081. Enabling the LAPI also requires the
    # local machine credentials file (the PreStart registers it with
    # `cscli machine add --auto` if missing).
    settings.lapi.credentialsFile = "/var/lib/crowdsec/lapi-secrets.yaml";
    settings.general.api.server = {
      enable = true;
      listen_uri = "127.0.0.1:8081";
    };

    localConfig.acquisitions = [
      {
        source = "journalctl";
        journalctl_filter = [ "_SYSTEMD_UNIT=stalwart.service" ];
        labels.type = "stalwart";
      }
    ];

    localConfig.parsers.s01Parse = [
      {
        name = "local/stalwart-auth-failure";
        description = "Parse Stalwart SMTP/IMAP authentication failures";
        filter = "evt.Line.Labels.type == 'stalwart'";
        onsuccess = "next_stage";
        grok = {
          # TODO: replace with a real pattern once journal samples exist.
          pattern = "^__REPLACE_WITH_REAL_GROK__ %{DATA:raw}";
          apply_on = "message";
        };
        statics = [
          {
            meta = "log_type";
            value = "stalwart_auth_failure";
          }
          {
            meta = "service";
            value = "stalwart";
          }
        ];
      }
    ];

    localConfig.scenarios = [
      {
        type = "leaky";
        name = "local/stalwart-auth-bf";
        description = "Brute force against Stalwart SMTP/IMAP AUTH";
        filter = "evt.Meta.log_type == 'stalwart_auth_failure'";
        leakspeed = "10s";
        capacity = 5;
        groupby = "evt.Meta.source_ip";
      }
    ];

    localConfig.postOverflows.s01Whitelist = [
      {
        name = "local/whitelist-loopback";
        description = "Never ban local traffic";
        whitelist = {
          reason = "local";
          ip = [
            "127.0.0.1"
            "::1"
          ];
        };
      }
    ];
  };

  services.crowdsec-firewall-bouncer = {
    enable = true;
    registerBouncer.enable = true;
    settings.mode = "nftables";
  };
}
