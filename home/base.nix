_:

{
  programs.home-manager.enable = true;
  home = {
    username = "daniel";
    homeDirectory = "/home/daniel";
    sessionVariables = {
      SH_AUTH_SOCK = "/run/user/1000/keyring/ssh";
    };
    stateVersion = "25.05";
  };
}
