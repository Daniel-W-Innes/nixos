_:

{
  services.immich = {
    enable = true;
    group = "media";
    mediaLocation = "/mnt/immich";
    environment = {
      IMMICH_TELEMETRY_INCLUDE = "all";
      IMMICH_ALLOW_SETUP = "false";
    };
    settings = {
      library = {
        scan = {
          enabled = true;
          cronExpression = "0 00 * * *";
        };
        watch.enabled = true;
      };
      backup.database = {
        enabled = true;
        cronExpression = "0 05 * * *";
        keepLastAmount = 20;
      };
      metadata.faces.import = true;
      newVersionCheck.enabled = false;
      nightlyTasks = {
        clusterNewFaces = true;
        databaseCleanup = true;
        generateMemories = true;
        missingThumbnails = true;
        syncQuotaUsage = true;
        startTime = "01:00";
      };
      passwordLogin.enabled = true;
      reverseGeocoding.enabled = true;
      storageTemplate = {
        enabled = true;
        hashVerificationEnabled = true;
        template = "{{y}}/{{MM}}/{{dd}}/{{HH}}{{mm}}{{SSS}}_{{filename}}";
      };
    };
  };
}
