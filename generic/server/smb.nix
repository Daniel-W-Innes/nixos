{ config, ... }:

{
  boot.supportedFilesystems = [ "cifs" ];

  fileSystems."/mnt/immich" = {
    device = "//pumpkin.lc.brotherwolf.ca/Immich";
    fsType = "cifs";
    options = [
      "ro"
      "credentials=${config.age.secrets.immich-smb-credentials.path}"
      "x-systemd.automount"
      "noauto"
      "nofail"
      "uid=immich"
      "gid=immich"
      "file_mode=0640"
      "dir_mode=0750"
    ];
  };
}