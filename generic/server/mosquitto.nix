{ config, secretsDir, ... }:

{
  age.secrets.mosquitto-hashed-passwd-shelly = {
    file = secretsDir + "/mosquitto-hashed-passwd-shelly.age";
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
        users."shelly" = {
          hashedPasswordFile = config.age.secrets.mosquitto-hashed-passwd-shelly.path;
          acl = [ "readwrite #" ];
        };
      }
    ];
  };
}
