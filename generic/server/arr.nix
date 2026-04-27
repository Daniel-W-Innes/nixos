{ config, lib, pkgs, ... }:

{
  vpnNamespaces.proton = {
    enable = true;
    wireguardConfigFile = config.age.secrets.proton-vpn.path;
    accessibleFrom = [
      "127.0.0.1/32"
    ];
    portMappings = [  { from = 9091; to = 9091; } ];
  };

  systemd.services.transmission.vpnConfinement = {
    enable = true;
    vpnNamespace = "proton";
  };

  systemd.services.transmission.serviceConfig.ExecStartPre = lib.mkAfter [
    (
      "+"
      + pkgs.writeShellScript "transmission-create-queue-json" ''
        queue_json='/var/lib/transmission/.config/transmission-daemon/queue.json'

        if [ ! -e "$queue_json" ]; then
          printf '[]\n' |
            install -D -m 600 -o transmission -g transmission /dev/stdin "$queue_json"
        fi
      ''
    )
  ];

  services.transmission = {
    enable = true;
    package = pkgs.transmission_4;
    credentialsFile = config.age.secrets.transmission.path;
    settings = {
      message-level = 3;
      encryption = 1;
      download-dir = "/mnt/media/downloads";
      incomplete-dir = "/mnt/media/downloads/incomplete";
      incomplete-dir-enabled = true;
      download-queue-enabled = false;
    };
  };
}
