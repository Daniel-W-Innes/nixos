_:

{
    services.dawarich = {
      enable = true;
      localDomain = "dawarich.lc.brotherwolf.ca";
      configureNginx = false;
      webPort = 3080;
      environment = {
        STORE_GEODATA = "true";
        TIME_ZONE = "America/Toronto";
    };
  };
}