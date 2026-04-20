{ config, ... }:

{
  services.cloudflared = {
    enable = true;
    tunnels = {
      "b91eab8b-a03d-4d28-ade2-6a87481f2ca8" = {
        credentialsFile = config.age.secrets.cloudflared-tunnel.path;
        default = "http_status:404";
        ingress = {
          "calibre.brotherwolf.ca".service = "https://localhost";
          "jellyfin.brotherwolf.ca".service = "https://localhost";
          "prometheus.brotherwolf.ca".service = "https://localhost";
          "grafana.brotherwolf.ca".service = "https://localhost";
        };
      };
    };
  };
}
