{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.prometheus.exporters.shelly;

  package = pkgs.buildGoModule {
    pname = "shelly-exporter";
    version = "0.1.0";
    src = ./shelly-exporter;
    # Run `nix build .#nixosConfigurations.<host>.config.services.prometheus.exporters.shelly.package`
    # to get the correct hash, then replace the line below.
    vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
in
{
  options.services.prometheus.exporters.shelly = {
    enable = lib.mkEnableOption "Shelly MQTT Prometheus exporter";

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to bind the exporter to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9129;
      description = "Port to bind the exporter to.";
    };

    mqttBroker = lib.mkOption {
      type = lib.types.str;
      default = "tcp://localhost:1883";
      description = "MQTT broker address.";
    };

    mqttClientID = lib.mkOption {
      type = lib.types.str;
      default = "shelly-exporter";
      description = "MQTT client ID.";
    };

    mqttTopic = lib.mkOption {
      type = lib.types.str;
      default = "+/status";
      description = "MQTT topic to subscribe to (use + for device ID wildcard).";
    };

    mqttUser = lib.mkOption {
      type = lib.types.str;
      description = "MQTT username (leave empty for anonymous).";
    };

    mqttPasswordPath = lib.mkOption {
      type = lib.types.path;
      description = "Path to a file containing the MQTT password.";
    };

    statusPollInterval = lib.mkOption {
      type = lib.types.str;
      default = "10s";
      description = "Interval between status_update commands sent to devices (e.g., \"30s\").";
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable debug logging in the exporter.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.prometheus-shelly-exporter = {
      description = "Shelly MQTT Prometheus exporter";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        DynamicUser = true;
        ExecStart = lib.escapeShellArgs (
          [
            "${package}/bin/nixos-shelly-exporter"
            "--web.host=${cfg.host}"
            "--web.port=${toString cfg.port}"
            "--mqtt.broker=${cfg.mqttBroker}"
            "--mqtt.client-id=${cfg.mqttClientID}"
            "--mqtt.topic=${cfg.mqttTopic}"
            "--mqtt.password-path=%d/mqtt-password"
            "--status.poll-interval=${cfg.statusPollInterval}"
          ]
          ++ lib.optional (cfg.mqttUser != "") "--mqtt.user=${cfg.mqttUser}"
          ++ lib.optional cfg.debug "--debug"
        );
        LoadCredential = [
          "mqtt-password:${cfg.mqttPasswordPath}"
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
