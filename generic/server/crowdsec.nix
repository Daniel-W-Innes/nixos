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
  # /etc/crowdsec/config.yaml. The bouncer module's register unit instead runs
  # the *bare* cscli (no -c, so it looks for that missing file) — replaced
  # below with the same logic plus an explicit -c.
  #
  # How cscli registers bouncers (crowdsec 1.7.8, verified empirically):
  # `cscli bouncers add` writes DIRECTLY into the sqlite db at
  # db_config.db_path — no HTTP roundtrip (which is why the module's register
  # unit sandboxes away all address families on purpose). The register unit
  # therefore must run as the same uid as crowdsec.service and use the LAPI's
  # real db — hence DynamicUser is disabled on both units below, so they share
  # the static `crowdsec` user and /var/lib/crowdsec.
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

  # Static user instead of DynamicUser: the register unit must share the
  # daemon's uid to write the LAPI sqlite db (see the let comment), and the
  # static crowdsec user is in systemd-journal (which a dynamic uid would not
  # be — journal acquisition would break). /var/lib/crowdsec is created by
  # crowdsec-setup's mkdir as this user.
  systemd.services.crowdsec.serviceConfig.DynamicUser = lib.mkForce false;

  services.crowdsec-firewall-bouncer = {
    enable = true;
    registerBouncer.enable = true;
    settings.mode = "nftables";
    settings.api_url = "http://127.0.0.1:8083/";
  };

  # The bouncer's LoadCredential reads the api key the register unit writes,
  # but the module requires the register unit without ordering after it, so
  # the bouncer can start (and fail at step CREDENTIALS) in parallel before
  # the key exists.
  systemd.services.crowdsec-firewall-bouncer.after = [
    "crowdsec-firewall-bouncer-register.service"
  ];

  # The module's register unit is broken on nixpkgs 26.05: bare cscli without
  # -c defaults to /etc/crowdsec/config.yaml (which nothing creates); its
  # DynamicUser=true gives it a different uid than crowdsec.service, so it
  # cannot write the LAPI db and its StateDirectory=crowdsec steals
  # /var/lib/crowdsec from the daemon (which then crash-loops); and its
  # SystemCallFilter blocks the chown-family cscli uses (SIGSYS). Replaced
  # with the same logic run as the static crowdsec user, with the config
  # passed explicitly.
  systemd.services.crowdsec-firewall-bouncer-register = {
    serviceConfig = {
      ExecStart = lib.mkForce [ registerBouncer ];
      DynamicUser = lib.mkForce false;
      RestrictAddressFamilies = lib.mkForce [ ];
      CapabilityBoundingSet = lib.mkForce null;
      SystemCallFilter = lib.mkForce null;
      StateDirectory = lib.mkForce "crowdsec-firewall-bouncer-register";
    };
  };
}
