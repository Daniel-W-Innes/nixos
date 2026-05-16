{ secretsDir, ... }:

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
}
