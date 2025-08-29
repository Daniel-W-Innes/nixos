{ ... }:

{
  system.autoUpgrade = {
    enable = true;
    flake = "github:Daniel-W-Innes/nixos";
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
