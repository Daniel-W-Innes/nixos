{ pkgs, ... }:

{
  home.packages = with pkgs; [
    firefox
    signal-desktop
    proton-vpn
    discord
    spotify
  ];
}
