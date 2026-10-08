{ pkgs, ... }:

{
  # Keybinds in hyprland.conf run this bare name from the session PATH.
  home.packages = [ pkgs.hyprwhspr-rs ];

  xdg.configFile."hyprwhspr-rs/config.jsonc".source = ./speech/config.jsonc;
}
