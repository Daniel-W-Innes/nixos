{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.prometheus.exporters.openweathermap;

  package = pkgs.buildGoModule {
    pname = "openweathermap-exporter";
    version = "0.1.0";
    src = ./openweathermap-exporter;
    vendorHash = "sha256-/ywjmv8lCjK0MFSgQf/LiW7uGw/rlP8EwL5sX25+dWc=";
  };
in
{
  options.services.prometheus.exporters.openweathermap = {
    enable = lib.mkEnableOption "OpenWeatherMap Prometheus exporter";

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to bind the exporter to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9876;
      description = "Port to bind the exporter to.";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to a file containing the OpenWeatherMap API key.";
    };

    coordsFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to a file containing the latitude and longitude, separated by a colon.";
    };

    language = lib.mkOption {
      type = lib.types.str;
      default = "EN";
      description = "Language code passed to the OpenWeatherMap client.";
    };

    refreshInterval = lib.mkOption {
      type = lib.types.str;
      default = "10m";
      description = "How often the exporter refreshes data from OpenWeatherMap.";
    };

    requestTimeout = lib.mkOption {
      type = lib.types.str;
      default = "15s";
      description = "HTTP timeout for requests to OpenWeatherMap.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.prometheus-openweathermap-exporter = {
      description = "OpenWeatherMap Prometheus exporter";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        DynamicUser = true;
        ExecStart = lib.escapeShellArgs [
          "${package}/bin/nixos-openweathermap-exporter"
          "--web.listen-address=${cfg.host}:${toString cfg.port}"
          "--api-key-file=%d/api-key"
          "--coords-file=%d/coords"
          "--language=${cfg.language}"
          "--refresh-interval=${cfg.refreshInterval}"
          "--request-timeout=${cfg.requestTimeout}"
        ];
        LoadCredential = [
          "api-key:${cfg.apiKeyFile}"
          "coords:${cfg.coordsFile}"
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
  };
}
