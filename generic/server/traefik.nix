{ lib, config, ... }:

{
  services.traefik = {
    enable = true;
    environmentFiles = [
      config.age.secrets.traefik-env.path
    ];
    staticConfigOptions = {
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
          resolvers = [ "1.1.1.1:53" "8.8.8.8:53" ];
          propagation.delayBeforeChecks = 5;
        };
      };

      api.dashboard = true;
      # Access the Traefik dashboard on <Traefik IP>:8080 of your server
      api.insecure = true;
      metrics.prometheus = {};
    };

    dynamicConfigOptions = {
      http.routers = {
        calibre = lib.mkIf config.services.calibre-web.enable {
          rule = "PathPrefix(`/calibre`)";
          service = "calibre";
        };
        jellyfin = lib.mkIf config.services.jellyfin.enable {
          rule = "PathPrefix(`/jellyfin`)";
          service = "jellyfin";
        };
        prometheus = lib.mkIf config.services.prometheus.enable {
          rule = "PathPrefix(`/prometheus`)";
          service = "prometheus";
        };
        grafana = lib.mkIf config.services.grafana.enable {
          rule = "PathPrefix(`/grafana`)";
          service = "grafana";
        };
      };
      http.services = {
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
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 8080 ];
}