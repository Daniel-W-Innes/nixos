{ config, ... }:

{
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
        "file_mode=0640"
        "dir_mode=0750"
      ];
    };

    "/mnt/jellyfin" = {
      device = "//pumpkin.lc.brotherwolf.ca/Jellyfin_configs";
      fsType = "cifs";
      options = [
        "credentials=${config.age.secrets.pumpkin-smb-credentials.path}"
        "x-systemd.automount"
        "noauto"
        "nofail"
        "uid=media"
        "gid=media"
        "file_mode=0640"
        "dir_mode=0750"
      ];
    };
  };
}