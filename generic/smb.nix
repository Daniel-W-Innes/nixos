{ secretsDir, ... }:

{
  age.secrets.pumpkin-smb-credentials = {
    file = secretsDir + /pumpkin-smb-credentials.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  boot.supportedFilesystems = [ "cifs" ];
  users.groups.media = {
    gid = 987;
  };
  users.users.media = {
    isSystemUser = true;
    uid = 990;
    group = "media";
  };
}
