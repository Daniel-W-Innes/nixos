{ config, secretsDir, ... }:

{
  age.secrets.pumpkin-smb-credentials = {
    file = secretsDir + /pumpkin-smb-credentials.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  boot.supportedFilesystems = [ "cifs" ];
  users.groups.media = { };
  users.users.media = {
    isSystemUser = true;
    group = "media";
  };

  fileSystems = {
    "/mnt/media" = {
      device = "//pumpkin.lc.brotherwolf.ca/Media";
      fsType = "cifs";
      options = [
        "credentials=${config.age.secrets.pumpkin-smb-credentials.path}"
        "x-systemd.automount"
        "noauto"
        "nofail"
        "uid=media"
        "gid=media"
        "file_mode=0660"
        "dir_mode=0770"
      ];
    };
    "/mnt/references" = {
      device = "//pumpkin.lc.brotherwolf.ca/Calibre";
      fsType = "cifs";
      options = [
        "credentials=${config.age.secrets.pumpkin-smb-credentials.path}"
        "x-systemd.automount"
        "noauto"
        "nofail"
        "uid=media"
        "gid=media"
        "file_mode=0660"
        "dir_mode=0770"
      ];
    };
    "/mnt/immich" = {
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
  };
}
