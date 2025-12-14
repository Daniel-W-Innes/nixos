{ pkgs, ... }:

{
  home.packages = with pkgs; [
    gopls
    gofumpt
  ];
  programs.helix = {
    enable = true;
    theme = "catppuccin_mocha";
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
