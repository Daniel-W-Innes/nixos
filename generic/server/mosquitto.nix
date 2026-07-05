{ config, secretsDir, ... }:

{
  age.secrets.mosquitto-passwd = {
    file = secretsDir + "/mosquitto-passwd.age";
    mode = "0400";
    owner = "mosquitto";
    group = "mosquitto";
  };

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        port = 1883;
        settings.allow_anonymous = false;
        users."myuser" = {
          hashedPasswordFile = config.age.secrets.mosquitto-passwd.path;
          acl = [ "readwrite #" ];
        };
      }
    ];
  };
}
