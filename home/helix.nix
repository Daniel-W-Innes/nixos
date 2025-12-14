{ pkgs, ... }:

{
  home.packages = with pkgs; [
    gcc
    go
    dlv
    gopls
    gofumpt
  ];
  programs.helix = {
    enable = true;
    settings.theme = "catppuccin_mocha";
    languages = {
      language-server = {
        gopls.command = "gopls";
      };
      language = [
        {
          name = "go";
          scope = "source.go";
          file-types = [ "go" ];
          auto-format = true;
          formatter.command = "gofumpt";
          language-servers = [ "gopls" ];
        }
      ];
    };
  };
}
