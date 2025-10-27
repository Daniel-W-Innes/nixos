{ config, ... }:

{
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [
      config.age.secrets.wifi.path
    ];

    profiles = {
      Homenet2nest = {
        connection = {
          id = "Homenet2nest";
          interface-name = "wlp1s0";
          type = "wifi";
          uuid = "04b67734-4174-47ed-a1ca-62bde7a0b19a";
        };
        ipv4 = {
          method = "auto";
        };
        ipv6 = {
          addr-gen-mode = "default";
          method = "auto";
        };
        proxy = { };
        wifi = {
          mode = "infrastructure";
          ssid = "Homenet2nest";
        };
        wifi-security = {
          auth-alg = "open";
          key-mgmt = "wpa-psk";
          psk = "$HOMENET2NEST_PSK";
        };
      };
      KAVIK = {
        connection = {
          id = "KAVIK";
          interface-name = "wlp1s0";
          type = "wifi";
          uuid = "acc183da-fbab-4758-b276-796cef853147";
        };
        ipv4 = {
          method = "auto";
        };
        ipv6 = {
          addr-gen-mode = "default";
          method = "auto";
        };
        proxy = { };
        wifi = {
          mode = "infrastructure";
          ssid = "KAVIK";
        };
        wifi-security = {
          auth-alg = "open";
          key-mgmt = "wpa-psk";
          psk = "$KAVIK_PSK";
        };
      };
      fruit_salad = {
        connection = {
          id = "fruit_salad";
          interface-name = "wlp1s0";
          type = "wifi";
          uuid = "8048e0f5-7bc3-418f-b8cb-906a434cc2c1";
        };
        ipv4 = {
          method = "auto";
        };
        ipv6 = {
          addr-gen-mode = "default";
          method = "auto";
        };
        proxy = { };
        wifi = {
          mode = "infrastructure";
          ssid = "fruit_salad";
        };
        wifi-security = {
          key-mgmt = "sae";
          psk = "$FRUIT_SALAD_PSK";
        };
      };
    };
  };
}
