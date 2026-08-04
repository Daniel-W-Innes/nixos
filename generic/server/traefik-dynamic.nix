{ config, lib, ... }:

let
  mkHostRulePublic = name: "Host(`${name}.brotherwolf.ca`)";
  mkHostRuleInternal = name: "Host(`${name}.lc.brotherwolf.ca`)";

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
      middleware ? null,
      public ? false,
    }:
    {
      inherit enable;
      url = mkBackendUrl { inherit host port; };
      inherit public;
    }
    // lib.optionalAttrs (healthCheck != null) {
      inherit healthCheck;
    }
    // lib.optionalAttrs (middleware != null) {
      inherit middleware;
    };

  targetData = import ./traefik-targets.nix {
    inherit config;
  };

  traefikTargets = lib.pipe targetData [
    (lib.filterAttrs (_: target: target.enable))
    (lib.mapAttrs (_: mkTarget))
  ];

  publicRouters = lib.pipe traefikTargets [
    (lib.filterAttrs (_: target: target.public or false))
    (lib.mapAttrs (
      name: target:
      {
        rule = mkHostRulePublic name;
        service = name;
        entryPoints = [ "websecure" ];
      }
      // lib.optionalAttrs (target ? middleware || true) {
        middlewares = [ "security-headers@file" ]
          ++ lib.optional (target ? middleware) target.middleware;
      }
    ))
  ];

  internalRouters = lib.mapAttrs (
    name: target:
    {
      rule = mkHostRuleInternal name;
      service = name;
      entryPoints = [ "websecure" ];
    }
    // lib.optionalAttrs (target ? middleware || true) {
      middlewares =
        [ "internal-only@file" "security-headers@file" ]
        ++ lib.optional (target ? middleware) target.middleware;
    }
  ) traefikTargets;

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
    routers = publicRouters // internalRouters // {
      dashboard = {
        rule = "Host(`traefik.lc.brotherwolf.ca`)";
        service = "api@internal";
        entryPoints = [ "websecure" ];
        middlewares = [ "internal-only@file" "security-headers@file" ];
      };
    };

    inherit services;

    middlewares = lib.mkMerge [
      {
        security-headers.headers = {
          frameDeny = true;
          contentTypeNosniff = true;
          browserXssFilter = true;
          referrerPolicy = "strict-origin-when-cross-origin";
          customFrameOptionsValue = "SAMEORIGIN";
          permissionsPolicy = "camera=(), microphone=(), geolocation=(), payment=(), usb=()";
          stsSeconds = 63072000;
          stsIncludeSubdomains = true;
          stsPreload = true;
          forceSTSHeader = true;
        };

        internal-only.ipAllowList = {
          sourceRange = [
            "10.0.0.0/8"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "127.0.0.1"
            "::1"
          ];
        };
      }
      (lib.mkIf config.services.loki.enable {
        loki-auth.basicAuth = {
          usersFile = "/run/traefik-loki-htpasswd";
        };
      })
    ];
  };

  tls.options.modern = {
    minVersion = "VersionTLS12";
    cipherSuites = [
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
      "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
      "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
      "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
      "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256"
      "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256"
    ];
    curvePreferences = [
      "X25519"
      "CurveP256"
      "CurveP384"
      "CurveP521"
    ];
    sniStrict = true;
    alpnProtocols = [
      "h2"
      "http/1.1"
    ];
  };
}
