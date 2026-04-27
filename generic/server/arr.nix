{ config, lib, pkgs, ... }:

{
  vpnNamespaces.proton = {
    enable = true;
    wireguardConfigFile = config.age.secrets.proton-vpn.path;
    accessibleFrom = [
      "0.0.0.0"
    ];
    portMappings = [  { from = 9091; to = 9091; } ];
  };

  systemd.services.transmission.vpnConfinement = {
    enable = true;
    vpnNamespace = "proton";
  };

  # This is a hack to ensure the queue.json file exists before transmission starts, as it doesn't create it on its own and fails if it doesn't exist.
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
