{ pkgs, ... }:

{
  boot.kernelPackages = pkgs.linuxPackages_latest;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.auto-optimise-store = true;
  networking = {
    networkmanager.enable = true;
    nftables.enable = true;
    firewall.enable = true;
  };
  time.timeZone = "America/Toronto";
  i18n.defaultLocale = "en_CA.UTF-8";
  services.gnome.gnome-keyring.enable = true;
  programs = {
    vim = {
      enable = true;
      defaultEditor = true;
    };
    zsh.enable = true;
    git = {
      enable = true;
      config = {
        push = {
          autoSetupRemote = true;
        };
      };
    };
  };
  users.users.daniel = {
    isNormalUser = true;
    description = "Daniel Innes";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };
  users.defaultUserShell = pkgs.zsh;
  environment.shells = with pkgs; [ zsh ];
  environment.systemPackages = with pkgs; [ git ];
  fonts.packages = with pkgs; [ nerd-fonts.roboto-mono ];
}
