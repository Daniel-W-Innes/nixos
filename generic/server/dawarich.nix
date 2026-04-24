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
      PHOTON_API_HOST = "localhost:2322";
      PHOTON_API_USE_HTTPS = "false";
    };
  };
  virtualisation.oci-containers.containers = {
    dawarich-photon = {
      image = "rtuszik/photon-docker:latest";
      environment = {
        UPDATE_STRATEGY = "PARALLEL";
        ENABLE_METRICS = "true";
        REGION = "ca"; # TODO: This should be removed once there is more storage available for geodata.
      };
      ports = [
        "127.0.0.1:2322:2322/tcp"
      ];
    };
  };
}
