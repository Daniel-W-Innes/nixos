{
  config,
  lib,
  ...
}:

let
  mkHostRule =
    name:
    lib.concatStringsSep " || " [
      "Host(`${name}.brotherwolf.ca`)"
      "Host(`${name}.lc.brotherwolf.ca`)"
    ];

  mkBackendUrl =
    {
      host ? "127.0.0.1",
      port,
    }:
    let
      normalizedHost =
        if host == "" || host == "0.0.0.0" then
          "127.0.0.1"
        else if host == "::" then
          "::1"
        else
          host;
      formattedHost = if lib.hasInfix ":" normalizedHost then "[${normalizedHost}]" else normalizedHost;
    in
    "http://${formattedHost}:${toString port}";

  mkArrTarget =
    service:
    let
      serviceConfig = config.services.${service};
    in
    {
      inherit (serviceConfig) enable;
      url = mkBackendUrl { inherit (serviceConfig.settings.server) port; };
      healthCheck = {
        path = "/ping";
        interval = "10s";
      };
    };

  arrTargets = lib.genAttrs [
    "prowlarr"
    "radarr"
    "sonarr"
    "lidarr"
    "readarr"
  ] mkArrTarget;

  traefikTargets = lib.filterAttrs (_: target: target.enable) ({
    calibre = {
      inherit (config.services.calibre-web) enable;
      url =
        let
          host = config.services.calibre-web.listen.ip;
          inherit (config.services.calibre-web.listen) port;
        in
        mkBackendUrl {
          inherit host port;
        };
      healthCheck = {
        path = "/login";
        interval = "10s";
      };
    };
    jellyfin = {
      inherit (config.services.jellyfin) enable;
      # The NixOS jellyfin module does not expose its HTTP port as a configurable option.
      url = mkBackendUrl { port = 8096; };
      healthCheck = {
        path = "/health";
        interval = "10s";
      };
    };
    prometheus = {
      inherit (config.services.prometheus) enable;
      url =
        let
          host = config.services.prometheus.listenAddress;
          inherit (config.services.prometheus) port;
        in
        mkBackendUrl {
          inherit host port;
        };
      healthCheck = {
        path = "/-/ready";
        interval = "10s";
      };
    };
    grafana = {
      inherit (config.services.grafana) enable;
      url =
        let
          host = config.services.grafana.settings.server.http_addr;
          port = config.services.grafana.settings.server.http_port;
        in
        mkBackendUrl {
          inherit host port;
        };
      healthCheck = {
        path = "/-/ready";
        interval = "10s";
      };
    };
    dawarich = {
      inherit (config.services.dawarich) enable;
      url =
        let
          port = config.services.dawarich.webPort;
        in
        mkBackendUrl { inherit port; };
    };
    transmission = {
      inherit (config.services.transmission) enable;
      url =
        let
          host = config.services.transmission.settings.rpc-bind-address;
          port = config.services.transmission.settings.rpc-port;
        in
        mkBackendUrl {
          inherit host port;
        };
    };
    navidrome = {
      inherit (config.services.navidrome) enable;
      url =
        let
          host = config.services.navidrome.settings.Address;
          port = config.services.navidrome.settings.Port;
        in
        mkBackendUrl {
          inherit host port;
        };
    };
    immich = {
      inherit (config.services.immich) enable;
      url = mkBackendUrl {
        inherit (config.services.immich)
          host
          port
          ;
      };
    };
  } // arrTargets);

  routers = lib.mapAttrs (name: _: {
    rule = mkHostRule name;
    service = name;
  }) traefikTargets;

  services = lib.mapAttrs (_: target: {
    loadBalancer = {
      servers = [
        { inherit (target) url; }
      ];
    }
    // lib.optionalAttrs (target ? healthCheck) {
      inherit (target) healthCheck;
    };
  }) traefikTargets;
in
{
  http = {
    inherit routers services;
  };
}
