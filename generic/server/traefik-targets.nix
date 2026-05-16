{ config, ... }:

let
  pingHealthCheck = {
    path = "/ping";
    interval = "10s";
  };

  readyHealthCheck = {
    path = "/-/ready";
    interval = "10s";
  };

  healthHealthCheck = {
    path = "/health";
    interval = "10s";
  };

  mkArrData =
    service:
    let
      serviceConfig = config.services.${service};
    in
    {
      inherit (serviceConfig) enable;
      inherit (serviceConfig.settings.server) port;
      healthCheck = pingHealthCheck;
    };

  arrTargetData = builtins.listToAttrs (
    map
      (name: {
        inherit name;
        value = mkArrData name;
      })
      [
        "prowlarr"
        "radarr"
        "sonarr"
        "lidarr"
        "readarr"
      ]
  );
in
{
  calibre = {
    inherit (config.services.calibre-server) enable host port;
  };
  jellyfin = {
    inherit (config.services.jellyfin) enable;
    # The NixOS jellyfin module does not expose its HTTP port as a configurable option.
    port = 8096;
    healthCheck = healthHealthCheck;
  };
  prometheus =
    let
      host = config.services.prometheus.listenAddress;
      inherit (config.services.prometheus) enable port;
    in
    {
      inherit enable host port;
      healthCheck = readyHealthCheck;
    };
  grafana =
    let
      inherit (config.services.grafana) enable;
      host = config.services.grafana.settings.server.http_addr;
      port = config.services.grafana.settings.server.http_port;
    in
    {
      inherit enable host port;
      healthCheck = readyHealthCheck;
    };
  dawarich =
    let
      inherit (config.services.dawarich) enable;
      port = config.services.dawarich.webPort;
    in
    {
      inherit enable port;
    };
  transmission =
    let
      inherit (config.services.transmission) enable;
      host = config.services.transmission.settings.rpc-bind-address;
      port = config.services.transmission.settings.rpc-port;
    in
    {
      inherit enable host port;
    };
  navidrome =
    let
      inherit (config.services.navidrome) enable;
      host = config.services.navidrome.settings.Address;
      port = config.services.navidrome.settings.Port;
    in
    {
      inherit enable host port;
    };
  immich = {
    inherit (config.services.immich) enable host port;
  };
  meilisearch =
    let
      inherit (config.services.meilisearch) enable;
      host = config.services.meilisearch.listenAddress;
      port = config.services.meilisearch.listenPort;
    in
    {
      inherit enable host port;
    };
  meilisearch-ui = {
    inherit (config.services.meilisearch) enable;
    port = 24900;
  };
  searx = 
    {
      inherit (config.services.searx) enable;
      port = 8888;
    };
}
// arrTargetData
