_:

{
  services.immich = {
    enable = true;
    settings = {
      storageTemplate = {
        enabled = true;
        hashVerificationEnabled = true;
        template = "{{y}}/{{MM}}/{{dd}}/{{HH}}{{mm}}{{SSS}}_{{filename}}";
      };
      reverseGeocoding.enabled = true;
    };
  };
}
