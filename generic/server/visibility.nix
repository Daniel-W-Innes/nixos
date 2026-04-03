{ config, ... }:

{
  environment.etc = {
    "grafana/node_exporter.json".source = ./grafana/node_exporter.json;
    "grafana/SMARTctl_exporter.json".source = ./grafana/SMARTctl_exporter.json;
    "grafana/unpoller_exporter_network.json".source = ./grafana/unpoller_exporter_network.json;
    "grafana/unpoller_exporter_uap.json".source = ./grafana/unpoller_exporter_uap.json;
    "grafana/unpoller_exporter_clients.json".source = ./grafana/unpoller_exporter_clients.json;
    "grafana/unpoller_exporter_dpi.json".source = ./grafana/unpoller_exporter_dpi.json;
    "grafana/unpoller_exporter_usw.json".source = ./grafana/unpoller_exporter_usw.json;
    "grafana/unpoller_exporter_pdu.json".source = ./grafana/unpoller_exporter_pdu.json;
    "grafana/unpoller_exporter_usg.json".source = ./grafana/unpoller_exporter_usg.json;
    "grafana/smokeping_exporter.json".source = ./grafana/smokeping_exporter.json;
    "grafana/qbittorrent_exporter.json".source = ./grafana/qbittorrent_exporter.json;
    "grafana/nvidia_gpu_exporter.json".source = ./grafana/nvidia_gpu_exporter.json;
  };
  services = {
    grafana = {
      enable = true;
      settings = {
        security = {
          admin_user = "admin";
          admin_password = "$__file{${config.age.secrets.grafana-admin-password.path}}";
        };
      };
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://localhost:9090";
            isDefault = true;
          }
        ];
        dashboards.settings.providers = [
          {
            name = "node-exporter-full";
            options.path = "/etc/grafana/node_exporter.json";
          }
          {
            name = "SMARTctl-exporter";
            options.path = "/etc/grafana/SMARTctl_exporter.json";
          }
          {
            name = "unpoller-exporter-network";
            options.path = "/etc/grafana/unpoller_exporter_network.json";
          }
          {
            name = "unpoller-exporter-uap";
            options.path = "/etc/grafana/unpoller_exporter_uap.json";
          }
          {
            name = "unpoller-exporter-clients";
            options.path = "/etc/grafana/unpoller_exporter_clients.json";
          }
          {
            name = "unpoller-exporter-dpi";
            options.path = "/etc/grafana/unpoller_exporter_dpi.json";
          }
          {
            name = "unpoller-exporter-usw";
            options.path = "/etc/grafana/unpoller_exporter_usw.json";
          }
          {
            name = "unpoller-exporter-pdu";
            options.path = "/etc/grafana/unpoller_exporter_pdu.json";
          }
          {
            name = "unpoller-exporter-usg";
            options.path = "/etc/grafana/unpoller_exporter_usg.json";
          }
          {
            name = "smokeping";
            options.path = "/etc/grafana/smokeping_exporter.json";
          }
          {
            name = "qbittorrent";
            options.path = "/etc/grafana/qbittorrent_exporter.json";
          }
          {
            name = "nvidia-gpu-exporter";
            options.path = "/etc/grafana/nvidia_gpu_exporter.json";
          }
        ];
      };
    };
    prometheus = {
      enable = true;
      extraFlags = [
        "--storage.tsdb.retention.size=1TB"
      ];
      globalConfig.scrape_interval = "10s"; # "1m"
      scrapeConfigs = [
        {
          job_name = "prometheus";
          static_configs = [
            {
              targets = [ "localhost:9100" ];
            }
          ];
        }
        {
          job_name = "copyparty";
          scheme = "https";
          metrics_path = "/.cpr/metrics";
          tls_config.insecure_skip_verify = false;
          basic_auth = {
            username = "metrics";
            password_file = config.age.secrets.prom-copyparty-metrics.path;
          };
          static_configs = [
            {
              targets = [ "localhost:3923" ];
            }
          ];
        }
        {
          job_name = "qbittorrent";
          static_configs = [
            {
              targets = [ "localhost:9177" ];
            }
          ];
        }
        {
          job_name = "node_exporter";
          static_configs = [
            {
              targets = [ 
                "onion.lc.brotherwolf.ca:9100"
                "cucamelon.lc.brotherwolf.ca:9100"
                "pumpkin.lc.brotherwolf.ca:9100"
              ];
            }
          ];
        }
        {
          job_name = "smartctl_exporter";
          static_configs = [
            {
              targets = [ 
                "onion.lc.brotherwolf.ca:9633"
                "cucamelon.lc.brotherwolf.ca:9633"
                "pumpkin.lc.brotherwolf.ca:9633"
              ];
            }
          ];
        }
        {
          job_name = "process_exporter";
          static_configs = [
            {
              targets = [ 
                "onion.lc.brotherwolf.ca:9256"
                "cucamelon.lc.brotherwolf.ca:9256"
                "pumpkin.lc.brotherwolf.ca:9256"
              ];
            }
          ];
        }
        {
          job_name = "nvidia_exporter";
          static_configs = [
            {
              targets = [
                "onion.lc.brotherwolf.ca:9835"
                "cucamelon.lc.brotherwolf.ca:9835"
                "pumpkin.lc.brotherwolf.ca:9835"
              ];
            }
          ];
        }
        {
          job_name = "grafana";
          static_configs = [
            {
              targets = [ "localhost:3000" ];
            }
          ];
        }
        {
          job_name = "unpoller";
          metrics_path = "/scrape";
          static_configs = [
            {
              targets = [ "https://radish.lc.brotherwolf.ca" ];
            }
          ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              target_label = "__param_target";
            }
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            {
              target_label = "__address__";
              replacement = "localhost:9130";
            }
          ];
        }
        {
          job_name = "mc-monitor";
          static_configs = [
            {
              targets = [ "localhost:9151" ];
            }
          ];
        }
        {
          job_name = "iperf3";
          metrics_path = "/probe";
          params.port = ["5201"];
          static_configs = [
            {
              targets = [
                "onion.lc.brotherwolf.ca"
                "pumpkin.lc.brotherwolf.ca"
              ];
            }
          ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              target_label = "__param_target";
            }
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            {
              target_label = "__address__";
              replacement = "localhost:9579";
            }
          ];
        }
        {
          job_name = "immich";
          static_configs = [
            {
              targets = [ "localhost:8082" ];
            }
          ];
        }
        {
          job_name = "domain";
          metrics_path = "/probe";
          static_configs = [
            {
              targets = [
                "brotherwolf.ca"
                "dwinnes.ca"
                "dwinnes.com"
              ];
            }
          ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              target_label = "__param_target";
            }
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            {
              target_label = "__address__";
              replacement = "localhost:9222";
            }
          ];
        }
        {
          job_name = "smokeping";
          static_configs = [
            {
              targets = [ "localhost:9374" ];
            }
          ];
        }
      ];
      exporters = {
        smokeping = {
          enable = true;
          port = 9374;
          hosts = [
            "173.33.65.81"
            "1.1.1.1"
            "8.8.8.8"
            "onion.lc.brotherwolf.ca"
            "cucamelon.lc.brotherwolf.ca"
            "pumpkin.lc.brotherwolf.ca"
            "www.google.com"
            "github.com"
          ];
        };
        domain = {
          enable = true;
          port = 9222;
        };
        unpoller = {
          enable = true;
          port = 9130;
          controllers = [
            {
              url = "https://radish.lc.brotherwolf.ca";
              user = "unpoller";
              pass = config.age.secrets.unpoller-password.path;
              save_ids = true;
              save_events = true;
              save_alarms = true;
              save_anomalies = true;
              save_dpi = true;
              save_sites = true;
              verify_ssl = false;
            }
          ];
        };
      };
    };
  };
  virtualisation.oci-containers.containers = {
    mc-monitor-exporter = {
      image = "docker.io/itzg/mc-monitor:latest";
      environment = {
        EXPORT_SERVERS = "173.33.65.81";
      };
      ports = [
        "127.0.0.1:9151:8080/tcp"
      ];
      cmd = [
        "export-for-prometheus"
      ];
    };
    iperf3-exporter = {
      image = "ghcr.io/edgard/iperf3_exporter:latest";
      ports = [
        "127.0.0.1:9579:9579/tcp"
      ];
    };
    qbittorrent-exporter = {
      image = "esanchezm/prometheus-qbittorrent-exporter:latest";
      environmentFiles = [ config.age.secrets.qbittorrent-webui-password.path ];
      environment = {
        QBITTORRENT_PORT = "24682";
        QBITTORRENT_HOST = "localhost";
        QBITTORRENT_USER = "admin";
      };
      ports = [
        "127.0.0.1:9177:8000/tcp"
      ];
    };
  };
}
