# CrowdSec watches stalwart's journal for auth failures and bans via the
# nftables bouncer. Stalwart has no native CrowdSec integration, and its
# built-in auto-ban is off unless Security.authBanRate is provisioned (no
# schema default in 1.x) — so CrowdSec is the only IP-based mitigation.
#
# Stalwart logging facts that shaped the parser (verified in 1.2.0 source
# and on melon's journal):
# - auth.failed is a debug-level event, so an EventTracingLevel object in
#   generic/server/stalwart.nix raises it to info.
# - The Journal tracer writes only the event description ("Authentication
#   failed") to MESSAGE; remoteIp etc. go to structured journald fields that
#   CrowdSec's journalctl acquisition does not read. A console tracer
#   (Tracer.objects.console, restricted to auth.failed) serializes the full
#   event onto stderr, which journald captures into MESSAGE — the line the
#   grok below matches. CrowdSec does not strip the journalctl prefix for
#   non-syslog types, so the pattern starts after it, unanchored.
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
          # Matches the console tracer line, e.g.:
          #   Nov 27 23:44:16 melon stalwart[1234]:
          #   2026-11-27T23:44:16Z INFO Authentication failed (auth.failed)
          #   listenerId = "submission", localPort = 587,
          #   remoteIp = 192.168.1.5, remotePort = 41234,
          #   accountName = "daniel"
          # Unanchored: the journalctl prefix before the RFC3339 timestamp
          # is left to its own devices, and the Journal tracer's bare
          # "Authentication failed" MESSAGE does not match.
          pattern = "%{TIMESTAMP_ISO8601:timestamp} %{LOGLEVEL:loglevel} Authentication failed \\(auth\\.failed\\) .*remoteIp = %{IP:remoteIp}";
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
          {
            meta = "source_ip";
            expression = "evt.Parsed.remoteIp";
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
  # be — journal acquisition would break).
  systemd.services.crowdsec.serviceConfig.DynamicUser = lib.mkForce false;

  # The module keeps ProtectSystem=strict + ReadWritePaths=/var/lib/crowdsec
  # and has no StateDirectory — crowdsec-setup is supposed to mkdir the dir in
  # ExecStartPre. But on systemd 260.5 a missing ReadWritePaths path fails
  # mount-namespace setup with 226/NAMESPACE ("No such file or directory")
  # *before* ExecStartPre runs, so a missing dir is unrecoverable (and the
  # register unit cascades — cscli can't mkdir /var/lib/crowdsec as the static
  # user either). Pre-create it via tmpfiles, which runs at boot/switch before
  # units start.
  systemd.tmpfiles.rules = [
    "d /var/lib/crowdsec 0750 crowdsec crowdsec -"
  ];

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
