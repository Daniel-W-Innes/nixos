{ pkgs, ... }:

{
  home.packages = with pkgs; [
    wl-clipboard
    alacritty
    playerctl
    brightnessctl
    pavucontrol
    kdePackages.dolphin
    kdePackages.dolphin-plugins
    kdePackages.qtsvg
  ];
  programs = {
    alacritty = {
      enable = true;
      settings = {
        window.opacity = 0.8;
      };
    };
    quickshell = {
      enable = true;
      configs.main = ./quickshell;
      # Inert without systemd.enable (ly never activates graphical-session.target):
      # the exec-once in hyprland.conf is what selects the config. Kept to
      # document which of the named configs is active.
      activeConfig = "main";
    };
    swaylock.enable = true;
  };
  services.hyprpolkitagent.enable = true;
  services.mako.enable = true;
  xdg.configFile = {
    "hypr/hyprland.conf".source = ./hyprland/hyprland.conf;
  };
}
