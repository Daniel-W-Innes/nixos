{ config, lib, ... }:

let
  mkHostRule =
    name:
    lib.concatStringsSep " || " [
      "Host(`${name}.brotherwolf.ca`)"
      "Host(`${name}.lc.brotherwolf.ca`)"
    ];

  mkBackendUrl =
    { host, port }:
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

  targetData = import ./traefik-targets.nix {
    inherit config;
  };

  traefikTargets = lib.pipe targetData [
    (lib.filterAttrs (_: target: target.enable))
    (lib.mapAttrs (_: mkTarget))
  ];

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
