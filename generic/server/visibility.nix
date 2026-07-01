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
    grafana-secret-key = lib.mkIf config.services.grafana.enable {
      file = secretsDir + /grafana-secret-key.age;
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
    influxdb-admin-password = lib.mkIf config.services.influxdb2.enable {
      file = secretsDir + /influxdb-admin-password.age;
      owner = "influxdb2";
      group = "influxdb2";
      mode = "0400";
    };
    influxdb-admin-token = lib.mkIf config.services.influxdb2.enable {
      file = secretsDir + /influxdb-admin-token.age;
      owner = "influxdb2";
      group = "influxdb2";
      mode = "0400";
    };
    influxdb-visibility-token = lib.mkIf config.services.influxdb2.enable {
      file = secretsDir + /influxdb-visibility-token.age;
      owner = "influxdb2";
      group = "grafana";
      mode = "0440";
    };
    konnected-influxdb-token = lib.mkIf config.services.prometheus.exporters.konnected.enable {
      file = secretsDir + /konnected-influxdb-token.age;
      owner = "influxdb2";
      group = "influxdb2";
      mode = "0400";
    };
    konnected-gotify-token = lib.mkIf config.services.prometheus.exporters.konnected.enable {
      file = secretsDir + /konnected-gotify-token.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    grafana-gotify-token = lib.mkIf config.services.gotify.enable {
      file = secretsDir + /grafana-gotify-token.age;
      owner = "grafana";
      group = "grafana";
      mode = "0400";
    };
  };

  services = {
    gotify = {
      enable = true;
      environment = {
        GOTIFY_SERVER_PORT = 60266;
      };
    };
    grafana = {
      enable = true;
      settings = {
        security = {
          admin_user = "admin";
          admin_password = "$__file{${config.age.secrets.grafana-admin-password.path}}";
          secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
        };
        feature_toggles = {
          enable = "dashboardScene,nestedProvisioning";
        };
      };
      provision = {
        enable = true;
        datasources.settings = {
          prune = true;
          datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              access = "proxy";
              url = "http://localhost:9090";
              isDefault = true;
            }
            {
              name = "InfluxDB";
              type = "influxdb";
              access = "proxy";
              url = "http://localhost:8086";
              database = "default";
              secureJsonData.token = "$__file{${config.age.secrets.influxdb-visibility-token.path}}";
              jsonData.version = "Flux";
              jsonData.organization = "visibility";
            }
          ];
        };
        alerting.contactPoints.settings = {
          contactPoints = [
            {
              orgId = 1;
              name = "gotify-direct";
              receivers = [
                {
                  uid = "gotify-direct-uid";
                  type = "webhook";
                  settings = {
                    url = "https://gotify.lc.brotherwolf.ca/message?token=$__file{${config.age.secrets.grafana-gotify-token.path}}";
                    httpMethod = "POST";
                    contentType = "application/json";
                    body = ''
                      {
                        "title": "{{ .CommonAnnotations.summary }}",
                        "message": "{{ .CommonAnnotations.description }}",
                        "priority": 2
                      }'';
                  };
                }
              ];
            }
          ];
        };
      };
    };
    prometheus = {
      enable = true;
      extraFlags = [
        "--storage.tsdb.retention.size=5TB"
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
                "cucamelon.lc.brotherwolf.ca:9100"
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
                "cucamelon.lc.brotherwolf.ca:9633"
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
                "cucamelon.lc.brotherwolf.ca:9256"
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
                "cucamelon.lc.brotherwolf.ca"
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
          job_name = "airzone-exporter";
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
        {
          job_name = "metar";
          static_configs = [
            {
              targets = [ "localhost:9750" ];
            }
          ];
        }
        {
          job_name = "konnected";
          static_configs = [
            {
              targets = [ "localhost:9877" ];
            }
          ];
        }
        {
          job_name = "influxdb";
          static_configs = [
            {
              targets = [ "localhost:8086" ];
            }
          ];
        }
        {
          job_name = "dnsmasq";
          static_configs = [
            {
              targets = [ "localhost:9153" ];
            }
          ];
        }
        {
          job_name = "tailscale";
          static_configs = [
            {
              targets = [ "localhost:9250" ];
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
        konnected = {
          enable = true;
          eventsURL = "http://alarm.lc.brotherwolf.ca/events";
          dbOrg = "visibility";
          dbBucket = "konnected";
          dbTokenPath = config.age.secrets.konnected-influxdb-token.path;
          gotifyEnabled = true;
          gotifyURL = "https://gotify.lc.brotherwolf.ca";
          gotifyTokenPath = config.age.secrets.konnected-gotify-token.path;
          gotifyAllowList = "Frontdoor,Backdoor";
        };
        dnsmasq = {
          enable = true;
          port = 9153;
        };
        tailscale = {
          enable = true;
          port = 9250;
        };
      };
    };
    influxdb2 = {
      enable = true;
      provision = {
        enable = true;
        organizations = {
          "visibility" = {
            auths = {
              "grafana" = {
                tokenFile = config.age.secrets.influxdb-visibility-token.path;
                allAccess = true;
              };
            };
          };
        };
        initialSetup = {
          bucket = "default";
          organization = "main";
          passwordFile = config.age.secrets.influxdb-admin-password.path;
          retention = 0;
          username = "admin";
          tokenFile = config.age.secrets.influxdb-admin-token.path;
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
    statuspage-exporter = {
      image = "ghcr.io/sergeyshevch/statuspage-exporter:latest";
      ports = [
        "127.0.0.1:9747:8080/tcp"
      ];
    };
    metar-exporter = {
      image = "ghcr.io/sgsunder/prometheus-metar:latest";
      cmd = [
        "CYOW"
        "CYYZ"
        "CYTZ"
        "CYND"
      ];
      ports = [
        "127.0.0.1:9750:3000/tcp"
      ];
    };
  };
}
