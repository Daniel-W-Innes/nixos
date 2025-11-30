{ ... }:

{
  networking.networkmanager.ensureProfiles.profiles = {
    "Bond connection 1" = {
      bond = {
        miimon = "100"; # Monitor MII link every 100ms
        mode = "802.3ad";
        xmit_hash_policy = "layer3+4"; # IP and TCP/UDP hash
      };
      connection = {
        id = "Bond connection 1";
        interface-name = "bond0"; # Make sure this matches the controller properties
        type = "bond";
      };
      ipv4 = {
        method = "auto";
      };
      ipv6 = { };
      proxy = { };
    };
    "bond0 port 1" = {
      connection = {
        id = "bond0 port 1";
        type = "ethernet";
        interface-name = "enp5s0";
        controller = "bond0";
        port-type = "bond";
      };
    };
    "bond0 port 2" = {
      connection = {
        id = "bond0 port 2";
        type = "ethernet";
        interface-name = "enp6s0";
        controller = "bond0";
        port-type = "bond";
      };
    };
    "bond0 port 3" = {
      connection = {
        id = "bond0 port 3";
        type = "ethernet";
        interface-name = "enp7s0";
        controller = "bond0";
        port-type = "bond";
      };
    };
    "bond0 port 4" = {
      connection = {
        id = "bond0 port 4";
        type = "ethernet";
        interface-name = "enp8s0";
        controller = "bond0";
        port-type = "bond";
      };
    };
  };
}
