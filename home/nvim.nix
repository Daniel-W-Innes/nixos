{ pkgs, ... }:

{
  home.packages = with pkgs; [
    gcc
    fd
  ];
  programs.neovim.enable = true;
  xdg.configFile = {
    "nvim" = {
      source = ./nvim;
      recursive = true;
    };
  };
}
