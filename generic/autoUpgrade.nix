{ self, config, ... }:

{
  system.autoUpgrade = {
    enable = true;
    flake = "/home/daniel/repos/nixos";
    dates = "18:00";
    randomizedDelaySec = "45min";
  };
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 7d --keep 10";
    flake = "/home/daniel/repos/nixos";
  };
}
