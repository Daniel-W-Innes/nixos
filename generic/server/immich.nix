_:

{
  services.immich = {
    enable = true;
    group = "media";
    mediaLocation = "/mnt/immich";
    environment = {
      IMMICH_TELEMETRY_INCLUDE = "all";
    };
  };
}