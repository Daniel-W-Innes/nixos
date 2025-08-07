{ pkgs, ... }:

{
  home.username = "daniel";
  home.homeDirectory = "/home/daniel";
  home.sessionVariables = {
    SH_AUTH_SOCK = "/run/user/1000/keyring/ssh";
  };
  programs.home-manager.enable = true;
  home.stateVersion = "25.05";
}
