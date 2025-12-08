{ config, ... }:

{
  users.users.copyparty = {
    shell = "/run/current-system/sw/bin/nologin";
    isNormalUser = false;
    extraGroups = [ "nas" ];
  };
  services.copyparty = {
    enable = true;
    user = "copyparty";
    settings = {
      z = true;

      e2d = true;
      e2dsa = true;
      e2ts = true;
      e2vu = true;

      dotpart = true;
      magic = true;

      ah-alg = "argon2";

      stats = true;
    };
    accounts = {
      daniel.passwordFile = config.age.secrets.copyparty-daniel.path;
      metrics.passwordFile = config.age.secrets.copyparty-metrics.path;
    };
    volumes = {
      "/" = {
        path = "/mnt/main";
        access = {
          rwmda = [ "daniel" ];
          a = [ "metrics" ];
        };
      };
    };
  };
}
