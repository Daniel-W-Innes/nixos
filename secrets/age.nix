{ ... }:

{
  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
    "/etc/ssh/ssh_host_ed25519_key_installer"
  ];
  age.secrets.wifi = {
    file = ./wifi.age;
    owner = "root";
    group = "root";
  };

  age.secrets.user-daniel = {
    file = ./user-daniel.age;
    owner = "root";
    group = "root";
  };
}
