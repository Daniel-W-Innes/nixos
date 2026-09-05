{ lib, config, ... }:

let
  # process-exporter matches each regex against the full space-joined argv;
  # anchor on the binary basename so other packages' store paths don't match
  # (e.g. prometheus-node-exporter, grafana-loki, forgejo-runner).
  bin = name: "(^|/)" + name + "( |$)";
in
{
  services = {
    prometheus.exporters = {
      node = {
        enable = true;
        port = 9100;
        openFirewall = true;
        firewallFilter = "-i enp8s0 -p tcp -m tcp --dport 9100";
      };
      process = {
        enable = true;
        port = 9256;
        openFirewall = true;
        firewallFilter = "-i enp8s0 -p tcp -m tcp --dport 9256";
        settings.process_names = [
          {
            name = "transmission";
            cmdline = [ (bin "transmission-daemon") ];
          }
          {
            name = "jellyfin";
            cmdline = [ (bin "jellyfin") ];
          }
          {
            name = "grafana";
            cmdline = [ (bin "grafana") ];
          }
          {
            name = "loki";
            cmdline = [ (bin "loki") ];
          }
          {
            name = "tempo";
            cmdline = [ (bin "tempo") ];
          }
          {
            name = "prometheus";
            cmdline = [ (bin "prometheus") ];
          }
          {
            name = "influxdb";
            cmdline = [ (bin "influxd") ];
          }
          {
            name = "forgejo";
            cmdline = [ (bin "forgejo") ];
          }
          {
            # *arr apps; Readarr runs via `dotnet Readarr.dll`, so the
            # case-sensitive names also keep exportarr (lowercase) out.
            name = "arr";
            cmdline = [
              "Prowlarr"
              "Radarr"
              "Sonarr"
              "Lidarr"
              "Readarr"
            ];
          }
          {
            name = "navidrome";
            cmdline = [ (bin "navidrome") ];
          }
          {
            name = "postgres";
            cmdline = [ (bin "postgres") ];
          }
          {
            name = "traefik";
            cmdline = [ (bin "traefik") ];
          }
          {
            # Binary is literally `server`; match the store path instead.
            name = "gotify";
            cmdline = [ "gotify-server" ];
          }
          {
            name = "uptime-kuma";
            cmdline = [ (bin "uptime-kuma") ];
          }
          {
            name = "forgejo-runner";
            cmdline = [ (bin "forgejo-runner") ];
          }
          {
            name = "meilisearch";
            cmdline = [ (bin "meilisearch") ];
          }
          {
            name = "meilisearch-ui";
            cmdline = [ "meilisearch-ui" ];
          }
          {
            # Binary is `.searxng-run-wrapped`; match the store path instead.
            name = "searxng";
            cmdline = [ "searxng" ];
          }
          {
            name = "immich";
            cmdline = [
              (bin "immich")
              (bin "immich-api")
            ];
          }
          {
            # Broad match: puma, sidekiq, and its redis/db workers all carry
            # `dawarich` in their argv.
            name = "dawarich";
            cmdline = [ "dawarich" ];
          }
          {
            # App container's node argv is generic; match podman's conmon
            # wrapper, which lives exactly as long as the container.
            name = "bookorbit";
            cmdline = [ "bookorbit-app" ];
          }
          {
            name = "mariadb";
            cmdline = [ (bin "mariadbd") ];
          }
          {
            name = "iperf3-exporter";
            cmdline = [ (bin "iperf3_exporter") ];
          }
          {
            name = "mc-monitor";
            cmdline = [ "mc-monitor" ];
          }
          {
            name = "metar-exporter";
            cmdline = [ "metar-exporter" ];
          }
          {
            name = "statuspage-exporter";
            cmdline = [ "statuspage-exporter" ];
          }
        ];
      };
      smartctl = lib.mkIf config.services.smartd.enable {
        enable = true;
        port = 9633;
        openFirewall = true;
        firewallFilter = "-i enp8s0 -p tcp -m tcp --dport 9633";
      };
      nvidia-gpu = lib.mkIf config.hardware.nvidia.enabled {
        enable = true;
        port = 9835;
        openFirewall = true;
        firewallFilter = "-i enp8s0 -p tcp -m tcp --dport 9835";
      };
    };
  };
  environment.etc = {
    "avahi/services/node-exporter.service".text = ''
      <?xml version="1.0" standalone='no'?>
          <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
          <service-group>
            <name replace-wildcards="yes">Node Exporter on %h</name>
            <service>
              <type>_http._tcp</type>
              <subtype>_node-exporter._sub._http._tcp</subtype>
              <port>9100</port>
              <txt-record>path=/metrics</txt-record>
            </service>
          </service-group>
    '';
    "avahi/services/smartctl-exporter.service" =
      lib.mkIf config.services.prometheus.exporters.smartctl.enable
        {
          text = ''
            <?xml version="1.0" standalone='no'?>
                  <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
                  <service-group>
                    <name replace-wildcards="yes">Smartctl Exporter on %h</name>
                    <service>
                      <type>_http._tcp</type>
                      <subtype>_smartctl-exporter._sub._http._tcp</subtype>
                      <port>9633</port>
                      <txt-record>path=/metrics</txt-record>
                    </service>
                  </service-group>
          '';
        };
    "avahi/services/process-exporter.service".text = ''
      <?xml version="1.0" standalone='no'?>
          <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
          <service-group>
            <name replace-wildcards="yes">Process Exporter on %h</name>
            <service>
              <type>_http._tcp</type>
              <subtype>_process-exporter._sub._http._tcp</subtype>
              <port>9256</port>
              <txt-record>path=/metrics</txt-record>
            </service>
          </service-group>
    '';
    "avahi/services/nvidia-gpu-exporter.service" =
      lib.mkIf config.services.prometheus.exporters.nvidia-gpu.enable
        {
          text = ''
            <?xml version="1.0" standalone='no'?>
                  <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
                  <service-group>
                    <name replace-wildcards="yes">Nvidia-gpu Exporter on %h</name>
                    <service>
                      <type>_http._tcp</type>
                      <subtype>_nvidia-gpu._sub._http._tcp</subtype>
                      <port>9835</port>
                      <txt-record>path=/metrics</txt-record>
                    </service>
                  </service-group>
          '';
        };
  };
}
