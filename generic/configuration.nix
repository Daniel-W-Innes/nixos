{ pkgs, ... }:

{
  boot.kernelPackages = pkgs.linuxPackages_latest;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  networking.networkmanager.enable = true;
  time.timeZone = "America/Toronto";
  i18n.defaultLocale = "en_CA.UTF-8";
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  programs = {
    sway = {
        enable = true;
        wrapperFeatures.gtk = true;
    };
    vim = {
        enable = true;
        defaultEditor = true;
    };
  };
  users.users.daniel = {
    isNormalUser = true;
    description = "Daniel Innes";
    extraGroups = [ "networkmanager" "wheel" ];
  };
  environment.systemPackages = with pkgs; [
    git
  ];
  fonts.packages = with pkgs; [
    nerd-fonts.roboto-mono
  ];
}