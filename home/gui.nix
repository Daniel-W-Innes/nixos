{ pkgs, ... }:

{
  home.packages = with pkgs; [
    firefox
    # signal-desktop # Removed for CVEs in pnpm-10.29.2
    proton-vpn
    discord
    spotify
  ];
}
