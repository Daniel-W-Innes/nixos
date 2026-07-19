{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.prometheus.exporters.google-health;

  package = pkgs.buildGoModule {
    pname = "google-health-exporter";
    version = "0.1.0";
    src = ./google-health-exporter;
    vendorHash = "sha256-GIrf/p/5sxODTjSuOgvthZWI488XduMrHC339b8AiQU=";
  };
in
{
  options.services.prometheus.exporters.google-health = {
    enable = lib.mkEnableOption "Google Health Prometheus exporter";

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to bind the exporter to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9878;
      description = "Port to bind the exporter to.";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a Google credentials JSON file. If null, Application Default Credentials are used.";
    };

    credentialsType = lib.mkOption {
      type = lib.types.enum [
        "authorized-user"
        "service-account"
        "impersonated-service-account"
        "external-account"
      ];
      default = "authorized-user";
      description = "Type of Google credentials JSON file to load when credentialsFile is set.";
    };

    dataTypes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "steps:daily"
        "distance:daily"
        "active-energy-burned:daily"
        "total-calories:daily"
      ];
      description = "Google Health data types to roll up. Each item may include a :daily or :physical suffix.";
    };

    defaultRollupMode = lib.mkOption {
      type = lib.types.enum [
        "daily"
        "physical"
      ];
      default = "daily";
      description = "Default rollup mode for data types without an explicit suffix.";
    };

    refreshInterval = lib.mkOption {
      type = lib.types.str;
      default = "10m";
      description = "How often the exporter refreshes data from Google Health.";
    };

    requestTimeout = lib.mkOption {
      type = lib.types.str;
      default = "30s";
      description = "HTTP timeout for each Google Health refresh.";
    };

    lookback = lib.mkOption {
      type = lib.types.str;
      default = "24h";
      description = "How far back each Google Health rollup request should query.";
    };

    physicalWindow = lib.mkOption {
      type = lib.types.str;
      default = "1h";
      description = "Aggregation window for physical-time rollups.";
    };

    dailyWindowDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Aggregation window size in days for daily rollups.";
    };

    dataSourceFamily = lib.mkOption {
      type = lib.types.str;
      default = "all-sources";
      description = "Google Health data source family to roll up.";
    };

    pageSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10000;
      description = "Maximum rollup data points to request per page.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.prometheus-google-health-exporter = {
      description = "Google Health Prometheus exporter";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        DynamicUser = true;
        ExecStart = lib.escapeShellArgs (
          [
            "${package}/bin/nixos-google-health-exporter"
            "--web.host=${cfg.host}"
            "--web.port=${toString cfg.port}"
            "--data-types=${lib.concatStringsSep "," cfg.dataTypes}"
            "--default-rollup-mode=${cfg.defaultRollupMode}"
            "--refresh-interval=${cfg.refreshInterval}"
            "--request-timeout=${cfg.requestTimeout}"
            "--lookback=${cfg.lookback}"
            "--physical-window=${cfg.physicalWindow}"
            "--daily-window-days=${toString cfg.dailyWindowDays}"
            "--data-source-family=${cfg.dataSourceFamily}"
            "--page-size=${toString cfg.pageSize}"
          ]
          ++ lib.optionals (cfg.credentialsFile != null) [
            "--credentials-file=%d/credentials"
            "--credentials-type=${cfg.credentialsType}"
          ]
        );
        LoadCredential = lib.optional (cfg.credentialsFile != null) "credentials:${cfg.credentialsFile}";
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
  };
}
