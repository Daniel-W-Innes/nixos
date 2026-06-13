{ pkgs, lib, secureBoot, ... }:

{
  boot = lib.mkMerge [
    {
      kernelPackages = pkgs.linuxPackages_latest;
    }
    (lib.mkIf (!secureBoot) {
      loader.systemd-boot = {
        enable = true;
        editor = false;
        configurationLimit = 10;
      };
    })
    (lib.mkIf secureBoot {
      lanzaboote = {
        enable = true;
        pkiBundle = "/var/lib/sbctl";
      };
      loader.systemd-boot.enable = lib.mkForce false;
    })
  ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;
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
      "media"
    ];
  };
  users.defaultUserShell = pkgs.zsh;
  environment.shells = with pkgs; [ zsh ];
  environment.systemPackages = with pkgs; [ git ];
  fonts.packages = with pkgs; [ nerd-fonts.roboto-mono ];
}
