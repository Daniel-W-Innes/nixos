{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.akvorado;
  yamlFormat = pkgs.formats.yaml { };

  # Construct the baseline settings from the explicit Nix options
  baseSettings = {
    orchestrator = {
      clickhouse = {
        servers = [ "${cfg.clickhouse.listenHost}:${toString cfg.clickhouse.listenPort}" ];
      };
      kafka = {
        brokers = [ "${cfg.kafka.listenHost}:${toString cfg.kafka.listenPort}" ];
      };
    };
    inlet = {
      flow = {
        inputs = [
          lib.mkIf
          cfg.inlet.netflow.enable
          {
            type = "udp";
            listen = "0.0.0.0:2055";
            workers = 6;
            decoder = "netflow";
          }
          lib.mkIf
          cfg.inlet.sflow.enable
          {
            type = "udp";
            listen = "0.0.0.0:6343";
            workers = 6;
            decoder = "sflow";
          }
        ];
      };
    };
    console = {
      listen = "0.0.0.0:8080";
    };
  };

  # Deep merge any extra settings the user provides on top of the base settings
  finalSettings = lib.recursiveUpdate baseSettings cfg.settings;
  configFile = yamlFormat.generate "akvorado.yaml" finalSettings;

in
{
  options.services.akvorado = with lib; {
    enable = mkEnableOption "Akvorado network flow collector and visualizer";

    image = mkOption {
      type = types.str;
      default = "quay.io/akvorado/akvorado:latest";
      description = "The container image to use for the podman deployments.";
    };

    zookeeper = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "The IP address Zookeeper listens on.";
      };
      port = mkOption {
        type = types.port;
        default = 2181;
        description = "The TCP port Zookeeper listens on.";
      };
      listenHost = mkOption {
        type = types.str;
        default = cfg.zookeeper.host;
        description = "The IP address Akvorado uses to reach Zookeeper.";
      };
      listenPort = mkOption {
        type = types.port;
        default = cfg.zookeeper.port;
        description = "The TCP port Akvorado uses to reach Zookeeper.";
      };
    };

    clickhouse = {
      host = mkOption {
        type = types.str;
        description = "The IP address ClickHouse listens on.";
      };
      port = mkOption {
        type = types.port;
        default = 9000;
        description = "The TCP port ClickHouse listens on.";
      };
      listenHost = mkOption {
        type = types.str;
        default = cfg.clickhouse.host;
        description = "The IP address Akvorado uses to reach ClickHouse's native TCP interface.";
      };
      listenPort = mkOption {
        type = types.port;
        default = cfg.clickhouse.port;
        description = "The TCP port Akvorado uses to reach ClickHouse's native TCP interface.";
      };
    };

    kafka = {
      host = mkOption {
        type = types.str;
        description = "The IP address Kafka listens on.";
      };
      port = mkOption {
        type = types.port;
        default = 9092;
        description = "The TCP port Kafka listens on.";
      };
      listenHost = mkOption {
        type = types.str;
        default = cfg.kafka.host;
        description = "The IP address Akvorado uses to reach Kafka.";
      };
      listenPort = mkOption {
        type = types.port;
        default = cfg.kafka.port;
        description = "The TCP port Akvorado uses to reach Kafka.";
      };
    };

    inlet = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "The NixOS host interface to bind the UDP flow ports to.";
      };
      netflow = mkOption {
        enable = mkDefault true;
        port = mkOption {
          type = types.port;
          default = 2055;
          description = "The UDP port for Netflow collection.";
        };
      };
      sflow = mkOption {
        enable = mkDefault true;
        port = mkOption {
          type = types.port;
          default = 6343;
          description = "The UDP port for sFlow collection.";
        };
      };
    };

    console = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "The NixOS host interface to bind the console Web UI port to.";
      };
      port = mkOption {
        type = types.port;
        default = 8080;
        description = "The TCP port for the Akvorado web console.";
      };
    };

    settings = mkOption {
      inherit (yamlFormat) type;
      default = { };
      description = "Extra configuration for Akvorado. Deep merged with the generated defaults.";
    };
  };

  config = lib.mkIf cfg.enable {
    services = {
      zookeeper = {
        enable = lib.mkDefault true;
        inherit (cfg.zookeeper) port;
        listenAddress = cfg.zookeeper.host;
      };
      apache-kafka = {
        enable = lib.mkDefault true;
        settings = {
          "zookeeper.connect" = [ "${cfg.zookeeper.listenHost}:${toString cfg.zookeeper.listenPort}" ];
          "listeners" = "PLAINTEXT://${cfg.kafka.host}:${toString cfg.kafka.port}";
          "offsets.topic.replication.factor" = 1;
          "transaction.state.log.replication.factor" = 1;
          "transaction.state.log.min.isr" = 1;
        };
      };
      clickhouse = {
        enable = lib.mkDefault true;
        settings = {
          server = {
            listen_host = cfg.clickhouse.host;
            tcp_port = cfg.clickhouse.port;
          };
        };
      };
    };

    virtualisation.oci-containers.containers = {
      akvorado-orchestrator = {
        inherit (cfg) image;
        cmd = [ "orchestrator" ];
        volumes = [ "${configFile}:/etc/akvorado/akvorado.yaml:ro" ];
      };

      akvorado-inlet = {
        inherit (cfg) image;
        cmd = [ "inlet" ];
        volumes = [ "${configFile}:/etc/akvorado/akvorado.yaml:ro" ];
        dependsOn = [ "akvorado-orchestrator" ];
        ports = [
          "${cfg.inlet.host}:${toString cfg.inlet.netflowPort}:2055/udp"
          "${cfg.inlet.host}:${toString cfg.inlet.sflowPort}:6343/udp"
        ];
      };

      akvorado-outlet = {
        inherit (cfg) image;
        cmd = [ "outlet" ];
        volumes = [ "${configFile}:/etc/akvorado/akvorado.yaml:ro" ];
        dependsOn = [ "akvorado-orchestrator" ];
      };

      akvorado-console = {
        inherit (cfg) image;
        cmd = [ "console" ];
        volumes = [ "${configFile}:/etc/akvorado/akvorado.yaml:ro" ];
        dependsOn = [ "akvorado-orchestrator" ];
        ports = [
          "${cfg.console.host}:${toString cfg.console.port}:8080/tcp"
        ];
      };
    };

    systemd.services."podman-akvorado-orchestrator" = {
      after = [
        "zookeeper.service"
        "apache-kafka.service"
        "clickhouse.service"
      ];
      wants = [
        "zookeeper.service"
        "apache-kafka.service"
        "clickhouse.service"
      ];
    };
  };
}
