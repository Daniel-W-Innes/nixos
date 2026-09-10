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
      # nvidia-open 595.71.05 doesn't compile against kernel 7.2.x (strncpy
      # was removed from the kernel API, nixpkgs#554125). 595.99.02 has the
      # upstream strscpy fix and matches nixpkgs master's `production` entry.
      # Drop this override once nixos-26.05 backports the 595.99.02 bump.
      package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
        version = "595.99.02";
        sha256_64bit = "sha256-6HR3lYv3YwcFSTJL1a1slI66btIQ5EAFs+/4SUD24ew=";
        sha256_aarch64 = "sha256-CCqHZTN2KNOZ4yZp2rDcuRJp9pHfRw47k4m4dWnS/2w=";
        openSha256 = "sha256-T36x/jx8yQ8l3LFp1rZIrTfcSwbGy8YSAvXOUSptpb4=";
        settingsSha256 = "sha256-GYCcnxfKPrTCrsmd25sMyzfC5cqJQJx0c31haooyTYM=";
        persistencedSha256 = "sha256-VyKtF/HdHPQrHHK6opSO69M72LmnGZtauuchj9uuje8=";
      };
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
