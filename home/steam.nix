{ pkgs, ... }:

{
  home.packages = with pkgs; [
    steam-tui
    steamcmd
    r2modman
    protonup-qt
    prismlauncher
  ];
}
