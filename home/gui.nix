{ pkgs, ... }:

{
  home.packages = with pkgs; [
    firefox
    signal-desktop
    bitwarden
  ];
}
