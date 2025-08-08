{ pkgs, ... }:

{
  home.packages = with pkgs; [
    wl-clipboard
    alacritty
    wofi
    kdePackages.dolphin
    kdePackages.dolphin-plugins
    kdePackages.qtsvg
  ];
  programs = {
    swaylock.enable = true;
    waybar.enable = true;
  };

  xdg.configFile = {
    "waybar/config.jsonc".source = ./hyprland/waybar/config.jsonc;
    "waybar/style.css".source = ./hyprland/waybar/style.css;
    # "sway/config".source = ./sway/config;
    "hypr/hyprland.conf".source = ./hyprland/hyprland.conf;
  };
}
