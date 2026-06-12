_:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    tmp.useTmpfs = true;
  };

  networking.hostName = "cucamelon"; # Define your hostname.
}
