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

  mkTarget =
    {
      enable,
      port,
      host ? "127.0.0.1",
      healthCheck ? null,
    }:
    {
      inherit enable;
      url = mkBackendUrl { inherit host port; };
    }
    // lib.optionalAttrs (healthCheck != null) {
      inherit healthCheck;
    };

  pingHealthCheck = {
    path = "/ping";
    interval = "10s";
  };

  readyHealthCheck = {
    path = "/-/ready";
    interval = "10s";
  };

  mkArrTarget =
    service:
    let
      serviceConfig = config.services.${service};
    in
    mkTarget {
      inherit (serviceConfig) enable;
      inherit (serviceConfig.settings.server) port;
      healthCheck = pingHealthCheck;
    };

  arrTargets = lib.genAttrs [
    "prowlarr"
    "radarr"
    "sonarr"
    "lidarr"
    "readarr"
  ] mkArrTarget;

  traefikTargets = lib.filterAttrs (_: target: target.enable) ({
    calibre =
      let
        host = config.services.calibre-web.listen.ip;
        inherit (config.services.calibre-web) enable;
        inherit (config.services.calibre-web.listen) port;
      in
      mkTarget {
        inherit enable host port;
        healthCheck = {
          path = "/login";
          interval = "10s";
        };
      };
    jellyfin = mkTarget {
      inherit (config.services.jellyfin) enable;
      # The NixOS jellyfin module does not expose its HTTP port as a configurable option.
      port = 8096;
      healthCheck = {
        path = "/health";
        interval = "10s";
      };
    };
    prometheus =
      let
        host = config.services.prometheus.listenAddress;
        inherit (config.services.prometheus) enable port;
      in
      mkTarget {
        inherit enable host port;
        healthCheck = readyHealthCheck;
      };
    grafana =
      let
        inherit (config.services.grafana) enable;
        host = config.services.grafana.settings.server.http_addr;
        port = config.services.grafana.settings.server.http_port;
      in
      mkTarget {
        inherit enable host port;
        healthCheck = readyHealthCheck;
      };
    dawarich =
      let
        inherit (config.services.dawarich) enable;
        port = config.services.dawarich.webPort;
      in
      mkTarget {
        inherit enable port;
      };
    transmission =
      let
        inherit (config.services.transmission) enable;
        host = config.services.transmission.settings.rpc-bind-address;
        port = config.services.transmission.settings.rpc-port;
      in
      mkTarget {
        inherit enable host port;
      };
    navidrome =
      let
        inherit (config.services.navidrome) enable;
        host = config.services.navidrome.settings.Address;
        port = config.services.navidrome.settings.Port;
      in
      mkTarget {
        inherit enable host port;
      };
    immich = mkTarget {
      inherit (config.services.immich)
        enable
        host
        port
        ;
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
