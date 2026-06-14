{ config, lib, ... }:

with lib;

let
  cfg = config.services.bookorbit;
in
{
  options.services.bookorbit = {
    enable = mkEnableOption "BookOrbit digital reading service";

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "The address BookOrbit's web service will listen on.";
    };

    port = mkOption {
      type = types.port;
      default = 23155;
      description = "The port BookOrbit's web service will listen on.";
    };

    libraryPath = mkOption {
      type = types.str;
      description = "The absolute path to your book folder (e.g., your Calibre mount).";
    };

    hostUrl = mkOption {
      type = types.str;
      default = "http://${toString cfg.host}:${toString cfg.port}";
      description = "The primary fully qualified domain or local address for base loops.";
    };

    environmentFile = mkOption {
      type = types.path;
      description = "The absolute path to the encrypted age secret file providing variables.";
    };

    user = mkOption {
      type = types.str;
      default = "media";
      description = "The user to own the BookOrbit files and run the containers as.";
    };

    group = mkOption {
      type = types.str;
      default = "media";
      description = "The group to own the BookOrbit files and run the containers as.";
    };

    readOnly = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to mount the book library as read-only. Enabling this will prevent BookOrbit from modifying your existing Calibre library structure, but may limit some features.";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/lib/bookorbit/app 0770 ${cfg.user} ${cfg.group} -"
      "d /var/lib/bookorbit/postgres 0770 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.init-bookorbit-network =
      let
        inherit (config.virtualisation.oci-containers) backend;
        bin = if backend == "podman" then "${pkgs.podman}/bin/podman" else "${pkgs.docker}/bin/docker";
      in
      {
        description = "Create isolated BookOrbit ${backend} Network";
        after = [ "${backend}.service" ];
        requires = [ "${backend}.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig.Type = "oneshot";
        script = ''
          ${bin} network inspect bookorbit-net >/dev/null 2>&1 || \
          ${bin} network create bookorbit-net
        '';
      };

    virtualisation.oci-containers = {
      containers = {
        bookorbit-db = {
          image = "pgvector/pgvector:pg16";
          environment = {
            POSTGRES_USER = "bookorbit";
            POSTGRES_DB = "bookorbit";
            PGDATA = "/var/lib/postgresql/data/pgdata";
          };
          environmentFiles = [ cfg.environmentFile ];
          volumes = [ "/var/lib/bookorbit/postgres:/var/lib/postgresql/data" ];
          extraOptions = [ "--network=bookorbit-net" ];
        };
        bookorbit-app = {
          image = "ghcr.io/bookorbit/bookorbit:latest";
          ports = [ "${toString cfg.port}:3000" ];
          dependsOn = [ "bookorbit-db" ];
          environment = {
            NODE_ENV = "production";
            POSTGRES_HOST = "bookorbit-db";
            POSTGRES_PORT = "5432";
            POSTGRES_USER = "bookorbit";
            POSTGRES_DB = "bookorbit";
            APP_URL = cfg.hostUrl;
            PUID = toString config.users.users.${cfg.user}.uid;
            PGID = toString config.users.groups.${cfg.group}.gid;
          };
          environmentFiles = [ cfg.environmentFile ];
          volumes = [
            "${cfg.libraryPath}:/books:${if cfg.readOnly then "ro" else "rw"}"
            "/var/lib/bookorbit/app:/data"
          ];
          extraOptions = [ "--network=bookorbit-net" ];
        };
      };
    };
  };
}
