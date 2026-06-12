{ config, secretsDir, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    tmp.useTmpfs = true;
  };
  networking.hostName = "onion"; # Define your hostname.

  hardware = {
    graphics.enable = true;
    nvidia = {
      prime.offload.enable = false;
      modesetting.enable = true;
      powerManagement.enable = true;
      powerManagement.finegrained = false;
      open = true;
      nvidiaSettings = true;
    };
  };

  services.xserver.videoDrivers = [ "nvidia" ];
  age.secrets.user-daniel = {
    file = secretsDir + /user-daniel.age;
    owner = "root";
    group = "root";
  };
  users.users.daniel.hashedPasswordFile = config.age.secrets.user-daniel.path;
}
