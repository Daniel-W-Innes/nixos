{ pkgs, ... }:

{
  home.packages = with pkgs; [
    wl-clipboard
    alacritty
    wofi
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
      configs.lock = ./quickshell-lock;
      # Inert without systemd.enable (ly never activates graphical-session.target):
      # the exec-once in hyprland.conf is what selects the config. Kept to
      # document which of the named configs is active.
      activeConfig = "main";
    };
  };
  services.hyprpolkitagent.enable = true;
  services.mako.enable = true;
  xdg.configFile = {
    "hypr/hyprland.conf".source = ./hyprland/hyprland.conf;
  };
}
