{ config, ... }:

{
  vpnNamespaces.proton = {
    enable = true;
    wireguardConfigFile = config.age.secrets.proton-vpn.path;
    accessibleFrom = [
      "10.8.8.0/24"
    ];
    portMappings = [  { from = 9091; to = 9091; } ];
  };

  systemd.services.transmission.vpnConfinement = {
    enable = true;
    vpnNamespace = "proton";
  };

  services.transmission = {
    enable = true;
    credentialsFile = config.age.secrets.transmission.path;
    settings = {
      download-dir = "/mnt/media/downloads";
      incomplete-dir = "/mnt/media/downloads/incomplete";
      incomplete-dir-enabled = true;
    };
  };
}
