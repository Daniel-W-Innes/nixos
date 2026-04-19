_:

{
  services.immich = {
    enable = true;
    openFirewall = true;
    settings = {
      storageTemplate = {
        enabled = true;
        hashVerificationEnabled = true;
        template = "{{y}}/{{MM}}/{{dd}}/{{HH}}{{mm}}{{SSS}}_{{filename}}";
      };
      reverseGeocoding.enabled = true;
    };
    environment = {
      IMMICH_TELEMETRY_INCLUDE = "all";
    };
  };
}