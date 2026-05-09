{
  config,
  lib,
  secretsDir,
  ...
}:
{
  age.secrets.traefik-env = lib.mkIf config.services.traefik.enable {
    file = secretsDir + /traefik-env.age;
    owner = "traefik";
    group = "traefik";
    mode = "0400";
  };

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

    dynamicConfigOptions = import ./traefik-dynamic.nix {
      inherit config lib;
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
    8080
  ];
}
