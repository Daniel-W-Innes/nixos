{ pkgs, ... }:

{
  home.packages = with pkgs; [
    firefox
    signal-desktop
    bitwarden-desktop
    protonvpn-gui
    discord
    spotify
  ];
}
