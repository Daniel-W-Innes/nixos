{ pkgs, ... }:

{
  programs.niri = {
    enable = true;
    useNautilus = false;
  };
  environment.systemPackages = with pkgs; [
    xwayland-satellite
  ];
  qt = {
    enable = true;
    platformTheme = "gnome";
    style = "adwaita-dark";
  };
  xdg.portal.enable = false;
}
