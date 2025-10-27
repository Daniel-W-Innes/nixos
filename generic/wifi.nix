{ config, ... }:

{
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [
      config.age.secrets.wifi.path
    ];

    profiles = {
      Starlink = {
        connection = {
          id = "fruit_salad";
          type = "wifi";
        };
        ipv4 = {
          method = "auto";
        };
        ipv6 = {
          addr-gen-mode = "stable-privacy";
          method = "auto";
        };
        wifi = {
          mode = "infrastructure";
          ssid = "fruit_salad";
        };
        wifi-security = {
          key-mgmt = "wpa-psk";
          psk = "$FRUIT_SALAD_PSK";
        };
      };
    };
  };
}
