{ pkgs, ... }:

{
  imports = [
    ./base.nix
    ./term.nix
    ./hypr.nix
    ./gui.nix
    ./gpg.nix
  ];
}
