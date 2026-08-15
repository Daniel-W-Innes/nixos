{ config, lib, ... }:

{
  services.dawarich = {
    enable = true;
    localDomain = "dawarich.lc.brotherwolf.ca";
    configureNginx = false;
    webPort = 3080;
    environment = {
      RAILS_ENV = "production";
      STORE_GEODATA = "true";
      TIME_ZONE = "America/Toronto";
      PHOTON_API_HOST = "photon.komoot.io";
      PHOTON_API_USE_HTTPS = "true";
    };
  };

  preservation.preserveAt."/dawarich" = {
    directories = lib.mkIf config.services.dawarich.enable [
      "/var/lib/dawarich"
    ];
  };
}
