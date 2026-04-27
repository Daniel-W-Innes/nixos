{ config, lib, pkgs, ... }:

{
  vpnNamespaces.proton = {
    enable = true;
    wireguardConfigFile = config.age.secrets.proton-vpn.path;
    accessibleFrom = [
      "10.8.8.0/24"
      "127.0.0.1/32"
    ];
    portMappings = [  { from = 9091; to = 9091; } ];
    openVPNPorts = [ { port = config.services.transmission.settings.peer-port; protocol = "both"; } ];
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
      rpc-bind-address = "192.168.15.1";
      rpc-whitelist = "192.168.15.5";
      rpc-whitelist-enabled = true;
      rpc-host-whitelist = "transmission.brotherwolf.ca,transmission.lc.brotherwolf.ca";
      lpd-enabled = true;
      peer-port = 51413;
      port-forwarding-enabled = true;
    };
  };
}
