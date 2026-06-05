{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.prometheus.exporters.airzone;

  package = pkgs.buildGoModule {
    pname = "airzone-exporter";
    version = "0.1.0";
    src = ./airzone-exporter;
    vendorHash = "sha256-oeCSKwDKVwvYQ1fjXXTwQSXNl/upDE3WAAk680vqh3U=";
  };
in
{
  options.services.prometheus.exporters.airzone = {
    enable = lib.mkEnableOption "Airzone Prometheus exporter";

    email = lib.mkOption {
      type = lib.types.str;
      example = "me@example.com";
      description = "Airzone account email passed to `--email`.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.str;
      example = "/run/secrets/airzone-password";
      description = "Path to a file containing the Airzone account password, passed to `--password-file`.";
    };

    baseURL = lib.mkOption {
      type = lib.types.str;
      default = "https://m.airzonecloud.com/api/v1";
      description = "Airzone API base URL passed to `--base-url`.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to bind the exporter to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9922;
      description = "Port to bind the exporter to.";
    };

    requestTimeout = lib.mkOption {
      type = lib.types.str;
      default = "15s";
      example = "30s";
      description = "HTTP timeout for requests to Airzone.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.prometheus-airzone-exporter = {
      description = "Airzone Prometheus exporter";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        DynamicUser = true;
        ExecStart = lib.escapeShellArgs [
          "${package}/bin/nixos-airzone-exporter"
          "--web.host=${cfg.host}"
          "--web.port=${toString cfg.port}"
          "--email=${cfg.email}"
          "--password-file=%d/password"
          "--base-url=${cfg.baseURL}"
          "--request-timeout=${cfg.requestTimeout}"
        ];
        LoadCredential = [
          "password:${cfg.passwordFile}"
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
