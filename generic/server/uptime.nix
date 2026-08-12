{ config, secretsDir, lib, pkgs, ... }:

{
  age.secrets.uptime-kuma-db-password = {
    file = secretsDir + /uptime-kuma-db-password.age;
    owner = config.services.uptime-kuma.user;
    inherit (config.services.uptime-kuma) group;
    mode = "0400";
  };

  # MariaDB database container
  virtualisation.oci-containers.containers.uptime-kuma-mariadb = {
    image = "mariadb:13";
    environment = {
      MARIADB_DATABASE = "uptime_kuma";
      MARIADB_USER = "uptime_kuma";
      MARIADB_PASSWORD_FILE = "/run/secrets/db-password";
    };
    volumes = [
      "/var/lib/uptime-kuma/mariadb:/var/lib/mysql"
      "${config.age.secrets.uptime-kuma-db-password.path}:/run/secrets/db-password:ro"
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
      UPTIME_KUMA_DB_PASSWORD_FILE = config.age.secrets.uptime-kuma-db-password.path;
    };
  };

  systemd.services.uptime-kuma = {
    after = [ "${config.virtualisation.oci-containers.backend}-uptime-kuma-mariadb.service" ];
    requires = [ "${config.virtualisation.oci-containers.backend}-uptime-kuma-mariadb.service" ];

    # Avoid storing the password in the Nix store by using a runtime-sourced script
    preStart = let
      waitScript = pkgs.writeShellScript "uptime-kuma-wait-db" ''
        set -e
        PASSWORD="$(cat ${config.age.secrets.uptime-kuma-db-password.path})"
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
    in ''
      ${waitScript}
    '';
  };
}