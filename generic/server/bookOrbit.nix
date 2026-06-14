{
  config,
  secretsDir,
  lib,
  ...
}:

{
  bookorbit-env = lib.mkIf config.services.bookorbit.enable {
    file = secretsDir + /bookorbit-env.age;
    owner = "${config.services.bookorbit.user}";
    group = "${config.services.bookorbit.group}";
    mode = "0400";
  };

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

  services.bookorbit = {
    enable = true;
    libraryPath = "/mnt/references";
    environmentFile = config.age.secrets.bookorbit-env.path;
    readOnly = true;
  };
}
