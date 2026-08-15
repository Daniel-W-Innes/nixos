{
  config,
  secretsDir,
  lib,
  pkgs,
  ...
}:

{
  users.users.uptime-kuma = {
    isSystemUser = true;
    group = "uptime-kuma";
  };
  users.groups.uptime-kuma = { };

  age.secrets.uptime-kuma-db-password-mariadb = {
    file = secretsDir + /uptime-kuma-db-password.age;
    owner = "999";
    group = "999";
    mode = "0400";
  };

  age.secrets.uptime-kuma-db-password-uptime = {
    file = secretsDir + /uptime-kuma-db-password.age;
    owner = "uptime-kuma";
    group = "uptime-kuma";
    mode = "0400";
  };

  age.secrets.uptime-kuma-db-root-password-mariadb = {
    file = secretsDir + /uptime-kuma-db-root-password.age;
    owner = "999";
    group = "999";
    mode = "0400";
  };

  virtualisation.oci-containers.containers.uptime-kuma-mariadb = {
    image = "mariadb:12.3.2-ubi10";
    environment = {
      MARIADB_DATABASE = "uptime_kuma";
      MARIADB_USER = "uptime_kuma";
      MARIADB_PASSWORD_FILE = "/run/secrets/db-password";
      MARIADB_ROOT_PASSWORD_FILE = "/run/secrets/db-root-password";
    };
    volumes = [
      "/var/lib/uptime-kuma/mariadb:/var/lib/mysql"
      "${config.age.secrets.uptime-kuma-db-password-mariadb.path}:/run/secrets/db-password:ro"
      "${config.age.secrets.uptime-kuma-db-root-password-mariadb.path}:/run/secrets/db-root-password:ro"
    ];
    ports = [ "127.0.0.1:3306:3306" ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/uptime-kuma/mariadb 0700 999 999 -"
    "Z /var/lib/uptime-kuma/mariadb - 999 999 - -"
  ];

  services.uptime-kuma = {
    enable = true;
    settings = {
      UPTIME_KUMA_DB_TYPE = "mariadb";
      UPTIME_KUMA_DB_HOSTNAME = "127.0.0.1";
      UPTIME_KUMA_DB_PORT = "3306";
      UPTIME_KUMA_DB_NAME = "uptime_kuma";
      UPTIME_KUMA_DB_USERNAME = "uptime_kuma";
      UPTIME_KUMA_DB_PASSWORD_FILE = config.age.secrets.uptime-kuma-db-password-uptime.path;
    };
  };

  systemd.services.uptime-kuma.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "uptime-kuma";
    Group = "uptime-kuma";
  };

  systemd.services.uptime-kuma = {
    after = [ "${config.virtualisation.oci-containers.backend}-uptime-kuma-mariadb.service" ];
    requires = [ "${config.virtualisation.oci-containers.backend}-uptime-kuma-mariadb.service" ];

    preStart =
      let
        waitScript = pkgs.writeShellScript "uptime-kuma-wait-db" ''
          set -e
          PASSWORD="$(cat ${config.age.secrets.uptime-kuma-db-password-uptime.path})"
          until ${lib.getExe' pkgs.mariadb "mysql"} \
            -h 127.0.0.1 -P 3306 \
            -u uptime_kuma \
            -p"$PASSWORD" \
            -e "SELECT 1" &>/dev/null
          do
            echo "Waiting for MariaDB to be ready..."
            sleep 1
          done
        '';
      in
      ''
        ${waitScript}
      '';
  };

  preservation.preserveAt."/uptime-kuma" = {
    directories = lib.mkIf config.services.uptime-kuma.enable [
      "/var/lib/uptime-kuma"
    ];
  };
}
