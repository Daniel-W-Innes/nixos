{ pkgs, ... }:

{
  imports = [
    ./base.nix
    ./term.nix
    ./sway.nix
    ./gui.nix
  ];
}
