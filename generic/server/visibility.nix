{
  config,
  lib,
  secretsDir,
  ...
}:

{
  age.secrets = {
    prom-copyparty-metrics = lib.mkIf config.services.prometheus.enable {
      file = secretsDir + /copyparty-metrics.age;
      owner = "prometheus";
      group = "prometheus";
    };

    grafana-admin-password = lib.mkIf config.services.grafana.enable {
      file = secretsDir + /grafana-admin-password.age;
      owner = "grafana";
      group = "grafana";
      mode = "0400";
    };

    unpoller-password = lib.mkIf config.services.prometheus.exporters.unpoller.enable {
      file = secretsDir + /unpoller-password.age;
      owner = "unpoller-exporter";
      group = "unpoller-exporter";
      mode = "0400";
    };

    airzone-explorer = lib.mkIf config.services.airzone-explorer.enable {
      file = secretsDir + /airzone-explorer.age;
      owner = "airzone-explorer";
      group = "airzone-explorer";
      mode = "0400";
    };

    sonarr-api-key = lib.mkIf config.services.prometheus.exporters.exportarr-sonarr.enable {
      file = secretsDir + /sonarr-api-key.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    radarr-api-key = lib.mkIf config.services.prometheus.exporters.exportarr-radarr.enable {
      file = secretsDir + /radarr-api-key.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    lidarr-api-key = lib.mkIf config.services.prometheus.exporters.exportarr-lidarr.enable {
      file = secretsDir + /lidarr-api-key.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    prowlarr-api-key = lib.mkIf config.services.prometheus.exporters.exportarr-prowlarr.enable {
      file = secretsDir + /prowlarr-api-key.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    openweathermap-api-key = lib.mkIf config.services.prometheus.exporters.openweathermap.enable {
      file = secretsDir + /openweathermap-api-key.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };

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
    "grafana/nvidia_gpu_exporter.json".source = ./grafana/nvidia_gpu_exporter.json;
    "grafana/iperf3_exporter.json".source = ./grafana/iperf3_exporter.json;
    "grafana/mc_monitor_exporter.json".source = ./grafana/mc_monitor_exporter.json;
    "grafana/navidrome_exporter.json".source = ./grafana/navidrome_exporter.json;
    "grafana/exportarr_exporter.json".source = ./grafana/exportarr_exporter.json;
    "grafana/traefik_exporter.json".source = ./grafana/traefik_exporter.json;
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
            name = "nvidia-gpu-exporter";
            options.path = "/etc/grafana/nvidia_gpu_exporter.json";
          }
          {
            name = "iperf3-exporter";
            options.path = "/etc/grafana/iperf3_exporter.json";
          }
          {
            name = "mc-monitor-exporter";
            options.path = "/etc/grafana/mc_monitor_exporter.json";
          }
          {
            name = "navidrome-exporter";
            options.path = "/etc/grafana/navidrome_exporter.json";
          }
          {
            name = "exportarr-exporter";
            options.path = "/etc/grafana/exportarr_exporter.json";
          }
          {
            name = "traefik-exporter";
            options.path = "/etc/grafana/traefik_exporter.json";
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
          job_name = "jellyfin";
          static_configs = [
            {
              targets = [ "localhost:8096" ];
            }
          ];
        }
        {
          job_name = "prometheus";
          static_configs = [
            {
              targets = [ "localhost:9100" ];
            }
          ];
        }
        {
          job_name = "traefik";
          static_configs = [
            {
              targets = [ "localhost:8080" ];
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
              targets = [ "pumpkin.lc.brotherwolf.ca:30266" ];
            }
          ];
        }
        {
          job_name = "node_exporter";
          static_configs = [
            {
              targets = [
                "onion.lc.brotherwolf.ca:9100"
                "localhost:9100"
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
                "localhost:9256"
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
          scrape_interval = "1h";
          metrics_path = "/probe";
          params.port = [ "5201" ];
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
              targets = [
                "localhost:8081"
                "localhost:8082"
              ];
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
        {
          job_name = "navidrome";
          static_configs = [
            {
              targets = [ "localhost:4533" ];
            }
          ];
        }
        {
          job_name = "searx";
          basic_auth = {
            username = "metrics";
            password_file = config.age.secrets.searx-metrics-password.path;
          };
          static_configs = [
            {
              targets = [ "localhost:8888" ];
            }
          ];
        }
        {
          job_name = "airzone-explorer";
          static_configs = [
            {
              targets = [ "localhost:9922" ];
            }
          ];
        }
        {
          job_name = "exportarr";
          static_configs = [
            {
              targets = [
                "localhost:9708"
                "localhost:9709"
                "localhost:9710"
                "localhost:9711"
              ];
            }
          ];
        }
        {
          job_name = "openweathermap";
          static_configs = [
            {
              targets = [ "localhost:9876" ];
            }
          ];
        }
        {
          job_name = "statuspage";
          metrics_path = "/probe";
          static_configs = [
            {
              targets = [ 
                "https://mrshu.github.io/github-statuses/"
                "https://www.githubstatus.com/"
                "https://www.cloudflarestatus.com/"
                "https://status.qlikcloud.com/"
                "https://status.airzonecloud.com/"
                "https://www.dockerstatus.com/"
                "https://status.atlassian.com/"
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
              replacement = "localhost:9747";
            }
          ];
        }
      ];
      exporters = {
        exportarr-sonarr = {
          enable = true;
          port = 9708;
          url = "https://sonarr.lc.brotherwolf.ca";
          apiKeyFile = config.age.secrets.sonarr-api-key.path;
        };
        exportarr-radarr = {
          enable = true;
          port = 9709;
          url = "https://radarr.lc.brotherwolf.ca";
          apiKeyFile = config.age.secrets.radarr-api-key.path;
        };
        exportarr-lidarr = {
          enable = true;
          port = 9710;
          url = "https://lidarr.lc.brotherwolf.ca";
          apiKeyFile = config.age.secrets.lidarr-api-key.path;
        };
        exportarr-prowlarr = {
          enable = true;
          port = 9711;
          url = "https://prowlarr.lc.brotherwolf.ca";
          apiKeyFile = config.age.secrets.prowlarr-api-key.path;
        };
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
    airzone-explorer = {
      enable = true;
      email = "airzonecloud.crawling495@simplelogin.com";
      passwordFile = config.age.secrets.airzone-explorer.path;
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
    statuspage-exporter = {
      image = "ghcr.io/sergeyshevch/statuspage-exporter:latest";
      ports = [
        "127.0.0.1:9747:9747/tcp"
      ];
    };
  };
}
