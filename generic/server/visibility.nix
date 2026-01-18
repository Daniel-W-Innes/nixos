{ config, ... }:

{
  services.grafana.enable = true;
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
            replacement = "pumpkin.lc.brotherwolf.ca:9115";
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
            targets = [ "pumpkin.lc.brotherwolf.ca:61429" ];
          }
        ];
      }
      {
        job_name = "onion";
        static_configs = [
          {
            targets = [ "onion.lc.brotherwolf.ca:9100" ];
          }
        ];
      }
      {
        job_name = "cucamelon";
        static_configs = [
          {
            targets = [ "cucamelon.lc.brotherwolf.ca:9100" ];
          }
        ];
      }
    ];
  };
}
