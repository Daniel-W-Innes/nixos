_:

{
  virtualisation.oci-containers.containers = {
    homeassistant = {
      image = "ghcr.io/home-assistant/home-assistant:stable";
      volumes = [
        "/var/lib/homeassistant:/config"
      ];
      environment.TZ = "America/Toronto";
      extraOptions = [
        "--network=host"
      ];
    };
  };
}