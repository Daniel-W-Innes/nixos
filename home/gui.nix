{ pkgs, ... }:

{
  home.packages = with pkgs; [
    signal-desktop
    bitwarden-desktop
    protonvpn-gui
    discord
    spotify
  ];
}
