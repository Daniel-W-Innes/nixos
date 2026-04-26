_:

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

  users.groups.photon = {
    gid = 9011;
  };
  users.users.photon = {
    isSystemUser = true;
    group = "photon";
    uid = 9011;
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/dawarich-photon/data 0755 photon photon -"
  ];

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
      volumes = [
        "/var/lib/dawarich-photon/data:/photon/data"
      ];
    };
  };
}
