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
  services = {
    #pcscd.enable = true;
    #udev.packages = [ pkgs.yubikey-personalization ];
    gnome.gnome-keyring.enable = true;
    xserver.xkb = {
      layout = "us";
      variant = "";
    };
  };
  programs = {
    vim = {
      enable = true;
      defaultEditor = true;
    };
    zsh.enable = true;
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
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    openFirewall = true;
    firewallFilter = "-i br0 -p tcp -m tcp --dport 9100";
  };
}
