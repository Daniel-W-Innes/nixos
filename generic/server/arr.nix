{ config, ... }:

{
  imports = [ ./podman.nix ];

  environment.etc."qbittorrent/qBittorrent.conf".source = ./qbittorrent/qBittorrent.conf;

  virtualisation.oci-containers.containers = {
    gluetun = {
      image = "ghcr.io/qdm12/gluetun:latest";
      environmentFiles = [ config.age.secrets.gluetun-wireguard.path ];
      environment = {
        TZ = "America/Toronto";
        VPN_TYPE = "wireguard";
        VPN_SERVICE_PROVIDER = "protonvpn";
        # Adjust this to the country/server you want.
        SERVER_COUNTRIES = "Canada";
        FIREWALL_INPUT_PORTS = "8080,6881";
      };
      ports = [
        "8080:8080/tcp"
        "6881:6881/tcp"
        "6881:6881/udp"
      ];
      devices = [ "/dev/net/tun:/dev/net/tun" ];
      capabilities.NET_ADMIN = true;
      extraOptions = [ "--network=bridge" ];
    };

    qbittorrent = {
      image = "lscr.io/linuxserver/qbittorrent:latest";
      dependsOn = [ "gluetun" ];
      environment = {
        TZ = "America/Toronto";
        WEBUI_PORT = "8080";
      };
      volumes = [
        "/var/lib/qbittorrent:/config"
        # "/mnt/main/downloads:/downloads"
      ];
      extraOptions = [ "--network=container:gluetun" ];
    };
  };

  systemd.services.podman-qbittorrent = {
    preStart = ''
      set -eu

      conf_dir="/var/lib/qbittorrent/qBittorrent"
      conf_file="$conf_dir/qBittorrent.conf"
      secret_file="${config.age.secrets.qbittorrent-webui-password-pbkdf2.path}"

      install -d -m 0750 "$conf_dir"

      if [ ! -f "$conf_file" ]; then
        install -m 0640 /etc/qbittorrent/qBittorrent.conf "$conf_file"
      fi

      sed -i '/^WebUI\\Password_PBKDF2=/d' "$conf_file"
      printf '\n' >> "$conf_file"
      cat "$secret_file" >> "$conf_file"
    '';
  };
  # services = {
  #   jellyfin = {
  #     enable = true;
  #   };

  #   radarr = {
  #     enable = true;
  #   };

  #   sonarr = {
  #     enable = true;
  #   };

  #   lidarr = {
  #     enable = true;
  #   };

  #   prowlarr = {
  #     enable = true;
  #   };

  #   flaresolverr = {
  #     enable = true;
  #   };
  # };
}
