_:

{
  services.immich = {
    enable = true;
    group = "media";
    mediaLocation = "/mnt/immich";
    environment = {
      IMMICH_TELEMETRY_INCLUDE = "all";
    };
    settings = {
      backup.database = {
          enabled = true;
          cronExpression = "0 02 * * *";
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
        startTime = "00:00";
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
