{ config, ... }:

{
  environment.etc."grafana/node_exporter.json".source = ./grafana/node_exporter.json;

  services.grafana = {
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
      ];
    };
  };
  services.prometheus = {
    enable = true;
    extraFlags = [
      "--storage.tsdb.retention.size=1TB"
    ];
    globalConfig.scrape_interval = "10s"; # "1m"
    scrapeConfigs = [
      {
        job_name = "blackbox";
        metrics_path = "/probe";
        params.module = [
          "icmp"
          "dns"
          "http"
        ];
        static_configs = [
          {
            targets = [
              "onion.lc.brotherwolf.ca"
              "google.com"
              "radish.lc.brotherwolf.ca"
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
            replacement = "localhost:9115";
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
        job_name = "grafana";
        static_configs = [
          {
            targets = [ "localhost:3000" ];
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
    ];
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
    };
    blackbox-exporter = {
      image = "quay.io/prometheus/blackbox-exporter:latest";
      ports = [
        "127.0.0.1:9115:9115/tcp"
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
