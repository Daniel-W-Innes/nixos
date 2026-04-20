# /home/daniel/repos/nixos/generic/server/cloudflared.nix
{ config, ... }:

{
  services.cloudflared = {
    enable = true;
    tunnels = {
      "melon" = {
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
