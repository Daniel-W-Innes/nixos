{ config, secretsDir, lib, ... }:

{
  age.secrets = {
    forgejo-admin-password = {
      file = secretsDir + /forgejo-admin-password.age;
      owner = config.services.forgejo.user;
      inherit (config.services.forgejo) group;
      mode = "0400";
    };
    forgejo-db-password = {
      file = secretsDir + /forgejo-db-password.age;
      owner = "999";
      group = "999";
      mode = "0400";
    };
  };

  systemd.tmpfiles.rules = [
    "d /run/forgejo-db 0700 ${config.services.forgejo.user} ${config.services.forgejo.group}"
    "d /var/lib/forgejo/postgres 0700 999 999 -"
  ];

  virtualisation.oci-containers.containers.forgejo-db = {
    image = "postgres:16-alpine";
    environment = {
      POSTGRES_USER = "forgejo";
      POSTGRES_DB = "forgejo";
      POSTGRES_PASSWORD_FILE = "/run/secrets/db-password";
    };
    volumes = [
      "/var/lib/forgejo/postgres:/var/lib/postgresql/data"
      "${config.age.secrets.forgejo-db-password.path}:/run/secrets/db-password:ro"
      "/run/forgejo-db:/var/run/postgresql"
    ];
  };

  services.forgejo = {
    enable = true;
    database = {
      createDatabase = false;
      socket = "/run/forgejo-db";
      type = "postgres";
    };
    dump = {
      enable = true;
      type = "tar.zst";
      age = "7d";
      interval = "02:00";
    };
    settings = {
      server = {
        DOMAIN = "git.lc.brotherwolf.ca";
        ROOT_URL = "https://git.lc.brotherwolf.ca/";
        HTTP_PORT = 53505;
        HTTP_ADDR = "127.0.0.1";
        SSH_PORT = lib.head config.services.openssh.ports;
      };
      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
        ENABLE_BASIC_AUTHENTICATION = false;
        DEFAULT_USER_VISIBILITY = "limited";
        DEFAULT_ORG_VISIBILITY = "limited";
      };
      mailer.ENABLED = false;
    };
  };

  systemd.services.forgejo = {
    after = [ "${config.virtualisation.oci-containers.backend}-forgejo-db.service" ];
    requires = [ "${config.virtualisation.oci-containers.backend}-forgejo-db.service" ];
    preStart = ''
      ${lib.getExe config.services.forgejo.package} admin user create \
        --admin \
        --email "root@localhost" \
        --username daniel \
        --password "$(tr -d '\n' < ${config.age.secrets.forgejo-admin-password.path})" || true
    '';
  };
}