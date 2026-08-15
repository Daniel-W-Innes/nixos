{ pkgs, ... }:

{
  virtualisation.containers.enable = true;
  virtualisation = {
    podman = {
      enable = true;
      autoPrune.enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = false;
    };
    oci-containers.backend = "podman";
  };

  networking.firewall.interfaces."podman1".allowedUDPPorts = [ 53 ];

  environment.systemPackages = with pkgs; [
    dive
    podman-tui
  ];
}
