{ ... }:

{
  programs.neovim.enable = true;
  xdg.configFile = {
    "nix".source = ./sway/config;
  };
}
