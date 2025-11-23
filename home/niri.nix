{ pkgs, ... }:

{
  home.packages = with pkgs; [
    wl-clipboard
    swaybg
  ];
  programs = {
   alacritty = {
      enable = true;
      settings = {
        window.opacity = 0.8;
        window.decorations = "none";
      };
    };
    swaylock.enable = true;
    waybar.enable = true;
    fuzzel.enable = true;
  };
  services = {
    hyprpolkitagent.enable = true;
    mako.enable = true;
  };
  xdg.configFile = {
    "waybar/config.jsonc".source = ./hyprland/waybar/config.jsonc;
    "waybar/style.css".source = ./hyprland/waybar/style.css;
    "niri/config.kdl".source = ./niri/config.kdl;
    "fuzzel/fuzzel.ini".source = ./niri/fuzzel.ini;
    "wallpapers/forgeworld_by_martechi.png".source = ./niri/forgeworld_by_martechi.png;
  }; 
}
