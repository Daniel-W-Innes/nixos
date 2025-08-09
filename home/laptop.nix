{ pkgs, ... }:

{
  imports = [
    ./base.nix
    ./dark.nix
    ./term.nix
    ./hypr.nix
    ./gui.nix
    ./gpg.nix
  ];
}
