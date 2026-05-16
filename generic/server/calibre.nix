{ config, ... }:

{
  systemd.tmpfiles.rules = [
    "d /var/log/calibre 0755 calibre-server media -"
  ];

  fileSystems."/mnt/references" = {
    device = "//pumpkin.lc.brotherwolf.ca/References";
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

  services.calibre-server = {
    enable = true;
    group = "media";
    port = 23155;
    libraries = [
      "/mnt/references"
    ];
    extraFlags = [
      "--log=/var/log/calibre/calibre-server.log"
    ];
  };
}
