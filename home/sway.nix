{ pkgs, ... }:

{
  home.packages = with pkgs; [
    wl-clipboard
  ];
  programs = {
    swaylock.enable = true;
    waybar.enable = true;
  };

  xdg.configFile = {
    "waybar/config.jsonc".source = ./sway/waybar/config.jsonc;
    "waybar/style.css".source = ./sway/waybar/style.css;
    "sway/config".source = ./sway/config;
  };
}
