{
  config,
  lib,
  secretsDir,
  ...
}:

let
  cfg = config.services.mixarr;
in
{
  options.services.mixarr = {
    enable = lib.mkEnableOption "mixarr, the self-hosted MusicBrainz-backed discovery companion for Lidarr";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8687;
      description = ''
        mixarr HTTP port, published on host loopback for the traefik backend
        (mixarr.lc.brotherwolf.ca). The container app binds 0.0.0.0:3000; the
        bundled Caddy on container 443 is unused — traefik terminates TLS.
      '';
    };
  };

  config = lib.mkMerge [
    { services.mixarr.enable = lib.mkDefault true; }
    (lib.mkIf cfg.enable {
      age.secrets.mixarr-env = {
        file = secretsDir + /mixarr-env.age;
        owner = "root";
        group = "root";
        mode = "0400";
      };

      systemd.tmpfiles.rules = [
        # Upstream's compose bind-mounts a root-owned data dir, so the image
        # (rootful, s6-style) manages permissions inside it itself.
        "d /var/lib/mixarr 0755 root root -"
      ];

      virtualisation.oci-containers.containers.mixarr = {
        # Unified image: MariaDB + Redis + Caddy all bundled in one container,
        # so no sibling db container or custom network is needed. Upstream
        # pins versioned images over :latest (schema migrations).
        image = "ghcr.io/aquantumofdonuts/mixarr:v3.0.0";
        environment = {
          TZ = "America/Toronto";
          # Both set to the browsed URL (OAuth redirects key off BASE_URL);
          # FRONTEND_URL is the public URL behind the reverse proxy.
          BASE_URL = "https://mixarr.lc.brotherwolf.ca";
          FRONTEND_URL = "https://mixarr.lc.brotherwolf.ca";
        };
        # Contains only SESSION_SECRET (persistent session-signing key;
        # never rotate casually — it invalidates all sessions).
        environmentFiles = [ config.age.secrets.mixarr-env.path ];
        volumes = [
          "/var/lib/mixarr:/data"
        ];
        ports = [ "127.0.0.1:${toString cfg.port}:3000" ];
      };
    })
  ];
}
