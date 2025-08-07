# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.luks.devices."luks-a907665e-4d88-43ce-bc1e-4deee8ce9eab".device =
    "/dev/disk/by-uuid/a907665e-4d88-43ce-bc1e-4deee8ce9eab";
  networking.hostName = "cucamelon"; # Define your hostname.
  powerManagement.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
