{ pkgs, ... }:

{
  home.packages = with pkgs; [
    wl-clipboard
    alacritty
    playerctl
    brightnessctl
    pavucontrol
    libqalculate # qalc, for the launcher's >calc mode
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
      configs.launcher = ./quickshell/launcher;
      # Deliberately not systemd.enable: the bar stays on exec-once (it is
      # compositor-critical UI). With UWSM, graphical-session.target is active,
      # so the HM unit would work now — but exec-once in hyprland.conf is what
      # selects the config. Kept to document which of the named configs is active.
      activeConfig = "main";
    };
  };
  services.hyprpolkitagent.enable = true;
  services.mako.enable = true;
  xdg.configFile = {
    "hypr/hyprland.conf".source = ./hyprland/hyprland.conf;
  };
}
