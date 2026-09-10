{ config, immichPkgs, ... }:

{
  fileSystems."/mnt/immich" = {
    device = "//pumpkin.lc.brotherwolf.ca/Immich";
    fsType = "cifs";
    options = [
      "credentials=${config.age.secrets.pumpkin-smb-credentials.path}"
      "x-systemd.automount"
      "noauto"
      "nofail"
      "uid=immich"
      "gid=media"
      "file_mode=0660"
      "dir_mode=0770"
    ];
  };

  services.immich = {
    enable = true;
    # immich from unstable: upstream moves fast and nixos-26.05 lags into
    # versions flagged insecure (e.g. 2.7.5).
    package = immichPkgs.immich;
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
