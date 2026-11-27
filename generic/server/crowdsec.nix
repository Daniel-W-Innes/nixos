# CrowdSec watches stalwart's journal for auth failures and bans via the
# nftables bouncer. Stalwart has no native CrowdSec integration; its built-in
# auto-ban (server.auto-ban) stays on as a second layer.
#
# The parser below is a defensive scaffold: the grok matches nothing yet, so
# no stalwart event (and therefore no ban) is produced until a real pattern
# from captured journal samples replaces the placeholder — see
# docs/debug/mail.md for the cscli explain loop.
#
# Ports on melon: 8080 = traefik metrics, 8081/8082 = immich metrics
# (generic/server/visibility.nix), so the LAPI lives on 8083.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # The crowdsec module generates its config as a store path and passes it to
  # the daemon and its cscli wrapper with -c; nothing writes
  # /etc/crowdsec/config.yaml. The bouncer module's register unit runs the
  # *bare* cscli binary (no -c, so it looks for that missing file) and also
  # declares StateDirectory=crowdsec with DynamicUser=true — on first
  # activation systemd's state-dir migration steals /var/lib/crowdsec from
  # crowdsec.service, which then crash-loops. The unit is replaced below with
  # a minimal root-run one that passes the config explicitly.
  # JSON is valid YAML for crowdsec's yaml parser, and builtins.toJSON avoids
  # the pkgs.formats.yaml API (which evaluates differently inside the module
  # system — the vendored stalwart module uses formats.json the same way).
  crowdsecConfigFile = pkgs.writeText "crowdsec.json" (
    builtins.toJSON config.services.crowdsec.settings.general
  );

  registerBouncer = pkgs.writeShellScript "crowdsec-firewall-bouncer-register" ''
    set -e
    cscli=${lib.getExe' config.services.crowdsec.package "cscli"}
    jq=${lib.getExe pkgs.jq}
    key=/var/lib/crowdsec-firewall-bouncer-register/api-key.cred
    # Same logic as the module's register script, but with -c so cscli finds
    # the real config (whose listen_uri also tells cscli the LAPI URL).
    if "$cscli" -c ${crowdsecConfigFile} bouncers list --output json \
        | "$jq" -e -- 'any(.[]; .name == "crowdsec-firewall-bouncer")' >/dev/null; then
      # Bouncer already registered. Verify the API key is still present.
      if [ ! -f "$key" ]; then
        echo "Bouncer registered but API key is not present"
        exit 1
      fi
    else
      rm -f "$key"
      if ! "$cscli" -c ${crowdsecConfigFile} bouncers add --output raw -- crowdsec-firewall-bouncer >"$key"; then
        rm -f "$key"
        exit 1
      fi
    fi
  '';
in
{
  services.crowdsec = {
    enable = true;

    # Local API for the firewall bouncer, on 8083 (8080 = traefik metrics,
    # 8081/8082 = immich metrics). The machine credentials file is registered
    # by crowdsec-setup on first start if missing.
    settings.lapi.credentialsFile = "/var/lib/crowdsec/lapi-secrets.yaml";
    settings.general.api.server = {
      enable = true;
      listen_uri = "127.0.0.1:8083";
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
    settings.api_url = "http://127.0.0.1:8083/";
  };

  # The module's register unit is broken on nixpkgs 26.05 (see the let-block
  # comment): bare cscli without -c defaults to /etc/crowdsec/config.yaml,
  # which nothing creates, and its StateDirectory=crowdsec + DynamicUser=true
  # steals crowdsec's state dir. Run the same logic as root with the config
  # passed explicitly. Root also sidesteps the module's sandbox: it dropped
  # all address families and capabilities, so cscli could not reach the LAPI
  # even with a config.
  systemd.services.crowdsec-firewall-bouncer-register = {
    serviceConfig = {
      ExecStart = lib.mkForce [ registerBouncer ];
      DynamicUser = lib.mkForce false;
      User = lib.mkForce null;
      Group = lib.mkForce null;
      RestrictAddressFamilies = lib.mkForce [ ];
      CapabilityBoundingSet = lib.mkForce null;
      StateDirectory = lib.mkForce "crowdsec-firewall-bouncer-register";
    };
  };
}
