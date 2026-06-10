# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

_:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot = {
    initrd.systemd.enable = true;
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    kernelParams = [
      "zswap.enabled=1" # enables zswap
      "zswap.compressor=lz4" # compression algorithm
      "zswap.max_pool_percent=20" # maximum percentage of RAM that zswap is allowed to use
      "zswap.shrinker_enabled=1" # whether to shrink the pool proactively on high memory pressure
    ];
  };
  networking.hostName = "melon";
  nixpkgs.config.allowUnfree = true;

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 64 * 1024; # 64 GiB
    }
  ];
  systemd.oomd.enable = true;
}
