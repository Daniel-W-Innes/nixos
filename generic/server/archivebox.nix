{
  config,
  lib,
  secretsDir,
  ...
}:

{
  systemd.tmpfiles.rules = [
    "d /mnt/archive-box 0755 media media -"
  ];

  age.secrets.archivebox-env = lib.mkIf config.services.bookorbit.enable {
    file = secretsDir + /archivebox-env.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  virtualisation.oci-containers.containers = {
    archive-box = {
      image = "archivebox/archivebox:latest";
      ports = [ "127.0.0.1:9099:8000/tcp" ];
      volumes = [
        "/mnt/archive-box:/data:rw"
      ];
      user = "${toString config.users.users.media.uid}:${toString config.users.groups.media.gid}";
      environment = {
        BASE_URL = "https://archivebox.lc.brotherwolf.ca";
      };
      environmentFiles = [ config.age.secrets.archivebox-env.path ];
    };
  };
}
