{ config, ... }:

{
  virtualisation.oci-containers.containers = {
    "arr-gluetun" = {
      image = "qmcgaw/gluetun:latest";
      ports = [
        "127.0.0.1:24682:8080/tcp"
        "127.0.0.1:49835:6789/tcp"
      ];
      capabilities.NET_ADMIN = true;
      environmentFiles = [ config.age.secrets.openvpn.path ];
      environment = {
        VPN_SERVICE_PROVIDER = "protonvpn";
        SERVER_COUNTRIES = "Switzerland,Spain";
      };
      extraOptions = [
        "--health-cmd=ping -c 1 www.google.com || exit 1"
        "--health-interval=60s"
        "--health-retries=3"
        "--health-start-period=20s"
        "--health-timeout=10s"
      ];
      podman.sdnotify = "healthy";
    };

    "arr-nzbget" = {
      image = "lscr.io/linuxserver/nzbget:latest";
      dependsOn = [ "arr-gluetun" ];
      volumes = [
        "/mnt/media/downloads:/downloads"
      ];
      extraOptions = [
        "--network=container:arr-gluetun"
      ];
    };

    "arr-qbittorrent" = {
      image = "linuxserver/qbittorrent:latest";
      dependsOn = [ "arr-gluetun" ];
      environment = {
        WEBUI_PORT = "8080";
      };
      volumes = [
        "/mnt/media/downloads:/downloads"
      ];
      extraOptions = [
        "--network=container:arr-gluetun"
      ];
    };
  };
}
