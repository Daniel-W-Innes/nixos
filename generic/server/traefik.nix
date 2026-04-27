{ lib, config, ... }:

{
  services.traefik = {
    enable = true;
    environmentFiles = [
      config.age.secrets.traefik-env.path
    ];
    staticConfigOptions = {
      global = {
        checkNewVersion = false;
        sendAnonymousUsage = true;
      };
      entryPoints = {
        web = {
          address = ":80";
          http.redirections.entrypoint = {
            to = "websecure";
            scheme = "https";
          };
        };

        websecure = {
          address = ":443";
          asDefault = true;
          http.tls.certResolver = "letsencrypt";
        };
      };

      log = {
        level = "INFO";
        filePath = "${config.services.traefik.dataDir}/traefik.log";
        format = "json";
      };

      certificatesResolvers.letsencrypt.acme = {
        email = "companies+letsencrypt@brotherwolf.ca";
        storage = "${config.services.traefik.dataDir}/acme.json";
        dnsChallenge = {
          provider = "cloudflare";
          resolvers = [
            "1.1.1.1:53"
            "8.8.8.8:53"
          ];
          propagation.delayBeforeChecks = 5;
        };
      };

      api = {
        dashboard = true;
        insecure = true;
      };
      metrics.prometheus = { };
    };

    dynamicConfigOptions.http = {
      routers = {
        calibre = lib.mkIf config.services.calibre-web.enable {
          rule = "Host(`calibre.brotherwolf.ca`) || Host(`calibre.lc.brotherwolf.ca`)";
          service = "calibre";
        };
        jellyfin = lib.mkIf config.services.jellyfin.enable {
          rule = "Host(`jellyfin.brotherwolf.ca`) || Host(`jellyfin.lc.brotherwolf.ca`)";
          service = "jellyfin";
        };
        prometheus = lib.mkIf config.services.prometheus.enable {
          rule = "Host(`prometheus.brotherwolf.ca`) || Host(`prometheus.lc.brotherwolf.ca`)";
          service = "prometheus";
        };
        grafana = lib.mkIf config.services.grafana.enable {
          rule = "Host(`grafana.brotherwolf.ca`) || Host(`grafana.lc.brotherwolf.ca`)";
          service = "grafana";
        };
        dawarich = lib.mkIf config.services.dawarich.enable {
          rule = "Host(`dawarich.brotherwolf.ca`) || Host(`dawarich.lc.brotherwolf.ca`)";
          service = "dawarich";
        };
        transmission = lib.mkIf config.services.transmission.enable {
          rule = "Host(`transmission.brotherwolf.ca`) || Host(`transmission.lc.brotherwolf.ca`)";
          service = "transmission";
        };
      };
      services = {
        calibre.loadBalancer = lib.mkIf config.services.calibre-web.enable {
          servers = [
            { url = "http://localhost:8083"; }
          ];
          healthCheck = {
            path = "/login";
            interval = "10s";
          };
        };
        jellyfin.loadBalancer = lib.mkIf config.services.jellyfin.enable {
          servers = [
            { url = "http://localhost:8096"; }
          ];
          healthCheck = {
            path = "/health";
            interval = "10s";
          };
        };
        prometheus.loadBalancer = lib.mkIf config.services.prometheus.enable {
          servers = [
            { url = "http://localhost:9090"; }
          ];
          healthCheck = {
            path = "/-/ready";
            interval = "10s";
          };
        };
        grafana.loadBalancer = lib.mkIf config.services.grafana.enable {
          servers = [
            { url = "http://localhost:3000"; }
          ];
          healthCheck = {
            path = "/-/ready";
            interval = "10s";
          };
        };
        dawarich.loadBalancer = lib.mkIf config.services.dawarich.enable {
          servers = [
            { url = "http://localhost:3080"; }
          ];
        };
        transmission.loadBalancer = lib.mkIf config.services.transmission.enable {
          servers = [
            { url = "http://192.168.15.1:9091"; }
          ];
        };
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
    8080
  ];
}
