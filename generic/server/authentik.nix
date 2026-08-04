{
  config,
  pkgs,
  lib,
  secretsDir,
  ...
}:
{
  age.secrets = {
    authentik-secret-key = {
      file = secretsDir + /authentik-secret-key.age;
      owner = "authentik";
      group = "authentik";
      mode = "0400";
    };
    authentik-db-password = {
      file = secretsDir + /authentik-db-password.age;
      owner = "authentik";
      group = "authentik";
      mode = "0400";
    };
  };

  users.groups.authentik = { };
  users.users.authentik = {
    isSystemUser = true;
    group = "authentik";
    home = "/var/lib/authentik";
  };

  systemd.tmpfiles.rules = [
    "d /run/authentik-db 0750 authentik authentik -"
    "d /var/lib/authentik/postgres 0700 999 999 -"
    "Z /var/lib/authentik/postgres - 999 999 - -"
  ];

  virtualisation.oci-containers.containers.authentik-db = {
    image = "postgres:16-alpine";
    environment = {
      POSTGRES_USER = "authentik";
      POSTGRES_DB = "authentik";
      POSTGRES_PASSWORD_FILE = "/run/secrets/db-password";
    };
    volumes = [
      "/var/lib/authentik/postgres:/var/lib/postgresql/data"
      "${config.age.secrets.authentik-db-password.path}:/run/secrets/db-password:ro"
      "/run/authentik-db:/var/run/postgresql"
    ];
  };

  systemd.services = {
    authentik-server = {
      description = "authentik server";
      wantedBy = [ "multi-user.target" ];
      after = [ "${config.virtualisation.oci-containers.backend}-authentik-db.service" ];
      requires = [ "${config.virtualisation.oci-containers.backend}-authentik-db.service" ];

      environment = {
        AUTHENTIK_POSTGRESQL__HOST = "/run/authentik-db";
        AUTHENTIK_POSTGRESQL__NAME = "authentik";
        AUTHENTIK_POSTGRESQL__USER = "authentik";
        AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS = "127.0.0.0/8,::1/128";
        AUTHENTIK_STORAGE__FILE__PATH = "/var/lib/authentik";
        AUTHENTIK_SECRET_KEY = "file://${config.age.secrets.authentik-secret-key.path}";
        AUTHENTIK_LOG_LEVEL = "info";
        AUTHENTIK_LISTEN__HTTP = "127.0.0.1:9000";
        AUTHENTIK_LISTEN__METRICS = "127.0.0.1:9300";
      };

      preStart = ''
        export PGPASSWORD="$(cat ${config.age.secrets.authentik-db-password.path})"
        ${lib.getExe' pkgs.postgresql "psql"} -h /run/authentik-db -U authentik -d authentik -c "SELECT 1"
      '';

      serviceConfig = {
        Type = "simple";
        User = "authentik";
        Group = "authentik";
        WorkingDirectory = "/var/lib/authentik";
        StateDirectory = "authentik";
        StateDirectoryMode = "0750";
        ExecStart = "${pkgs.writeShellScript "authentik-server-start" ''
          export AUTHENTIK_POSTGRESQL__PASSWORD="$(cat ${config.age.secrets.authentik-db-password.path})"
          exec ${pkgs.authentik}/bin/ak server
        ''}";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    authentik-worker = {
      description = "authentik worker";
      wantedBy = [ "multi-user.target" ];
      after = [ "${config.virtualisation.oci-containers.backend}-authentik-db.service" ];
      requires = [ "${config.virtualisation.oci-containers.backend}-authentik-db.service" ];

      environment = {
        AUTHENTIK_POSTGRESQL__HOST = "/run/authentik-db";
        AUTHENTIK_POSTGRESQL__NAME = "authentik";
        AUTHENTIK_POSTGRESQL__USER = "authentik";
        AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS = "127.0.0.0/8,::1/128";
        AUTHENTIK_STORAGE__FILE__PATH = "/var/lib/authentik";
        AUTHENTIK_SECRET_KEY = "file://${config.age.secrets.authentik-secret-key.path}";
        AUTHENTIK_LOG_LEVEL = "info";
        AUTHENTIK_LISTEN__HTTP = "127.0.0.1:9001";
        AUTHENTIK_LISTEN__METRICS = "127.0.0.1:9301";
      };

      preStart = ''
        export PGPASSWORD="$(cat ${config.age.secrets.authentik-db-password.path})"
        ${lib.getExe' pkgs.postgresql "psql"} -h /run/authentik-db -U authentik -d authentik -c "SELECT 1"
      '';

      serviceConfig = {
        Type = "simple";
        User = "authentik";
        Group = "authentik";
        WorkingDirectory = "/var/lib/authentik";
        StateDirectory = "authentik";
        StateDirectoryMode = "0750";
        ExecStart = "${pkgs.writeShellScript "authentik-worker-start" ''
          export AUTHENTIK_POSTGRESQL__PASSWORD="$(cat ${config.age.secrets.authentik-db-password.path})"
          exec ${pkgs.authentik}/bin/ak worker
        ''}";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
