{ lib, config, ... }:

{
  age.secrets = {
    wifi = lib.mkIf config.networking.networkmanager.enable {
      file = ./wifi.age;
      owner = "root";
      group = "root";
    };

    user-daniel = {
      file = ./user-daniel.age;
      owner = "root";
      group = "root";
    };

    prom-copyparty-metrics = lib.mkIf config.services.prometheus.enable {
      file = ./copyparty-metrics.age;
      owner = "prometheus";
      group = "prometheus";
    };

    grafana-admin-password = lib.mkIf config.services.grafana.enable {
      file = ./grafana-admin-password.age;
      owner = "grafana";
      group = "grafana";
      mode = "0400";
    };

    qbittorrent-webui-password = lib.mkIf config.services.prometheus.enable {
      file = ./qbittorrent-webui-password.env.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    unpoller-password = lib.mkIf config.services.prometheus.exporters.unpoller.enable {
      file = ./unpoller-password.age;
      owner = "unpoller-exporter";
      group = "unpoller-exporter";
      mode = "0400";
    };
    
    pumpkin-smb-credentials = {
      file = ./pumpkin-smb-credentials.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };
}
