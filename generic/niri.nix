{ pkgs, ... }:

{
  programs.niri.enable = true;
  environment.systemPackages = with pkgs; [
    xwayland-satellite
  ];
  qt = {
    enable = true;
    platformTheme = "gnome";
    style = "adwaita-dark";
  };
}
