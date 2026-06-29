{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.prometheus.exporters.konnected;

  package = pkgs.buildGoModule {
    pname = "konnected-exporter";
    version = "0.5.1";
    src = ./konnected-exporter;
    vendorHash = "sha256-y6XrU+3q8qTrABhHulrJYFLT96SI3OytOk7mFqsQC60=";
  };
in
{
  options.services.prometheus.exporters.konnected = {
    enable = lib.mkEnableOption "Konnected Prometheus exporter";

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to bind the exporter to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9877;
      description = "Port to bind the exporter to.";
    };

    gotifyAllowList = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Comma-separated list of entity names to allow Gotify notifications for. If empty, all entities are allowed.";
    };

    gotifyURL = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "URL of the Gotify server to send notifications to.";
    };

    gotifyTokenPath = lib.mkOption {
      type = lib.types.path;
      default = "/run/secrets/gotify_token";
      description = "Path to a file containing the Gotify application token.";
    };

    gotifyPriority = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Priority of the Gotify messages sent by the exporter.";
    };

    gotifyEnabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable Gotify notifications.";
    };

    eventsURL = lib.mkOption {
      type = lib.types.str;
      description = "URL to subscribe to for receiving events.";
    };

    dbURL = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:8086";
      description = "URL of the InfluxDB instance to write events to.";
    };

    dbTokenPath = lib.mkOption {
      type = lib.types.path;
      default = "/run/secrets/influxdb_token";
      description = "Path to a file containing the InfluxDB token.";
    };

    dbOrg = lib.mkOption {
      type = lib.types.str;
      description = "InfluxDB organization.";
    };

    dbBucket = lib.mkOption {
      type = lib.types.str;
      description = "InfluxDB bucket.";
    };

    setupDB = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to set up the InfluxDB database and initial user.";
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable debug logging in the exporter.";
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.services.prometheus-konnected-exporter = {
      description = "Konnected Prometheus exporter";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        DynamicUser = true;
        ExecStart = lib.escapeShellArgs [
          "${package}/bin/nixos-konnected-exporter"
          "--web.host=${cfg.host}"
          "--web.port=${toString cfg.port}"
          "--events.url=${cfg.eventsURL}"
          "--db.url=${cfg.dbURL}"
          "--db.token-path=%d/db-token"
          "--db.org=${cfg.dbOrg}"
          "--db.bucket=${cfg.dbBucket}"
          (lib.optionalString cfg.gotifyEnabled "--gotify.allowlist=${cfg.gotifyAllowList}")
          (lib.optionalString cfg.gotifyEnabled "--gotify.url=${cfg.gotifyURL}")
          (lib.optionalString cfg.gotifyEnabled "--gotify.token-path=%d/gotify-token")
          (lib.optionalString cfg.gotifyEnabled "--gotify.priority=${toString cfg.gotifyPriority}")
          (lib.optionalString cfg.gotifyEnabled "--gotify.enable")
          (lib.optionalString cfg.debug "--debug")
        ];
        LoadCredential = [
          "db-token:${cfg.dbTokenPath}"
        ] ++ lib.optionals cfg.gotifyEnabled [
          "gotify-token:${cfg.gotifyTokenPath}"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
      };
    };
    services.influxdb2.provision.organizations.${cfg.dbOrg} =
      lib.mkIf (cfg.setupDB && config.services.influxdb2.enable)
        {
          buckets.${cfg.dbBucket} = { };
          auths = {
            "konnected-writer" = {
              tokenFile = cfg.dbTokenPath;
              writeBuckets = [ cfg.dbBucket ];
            };
          };
        };
  };
}
