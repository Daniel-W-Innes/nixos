{ nixpkgs, ... }:

{
  programs.nvf = {
    enable = true;
    settings.vim = {
      viAlias = false;
      vimAlias = true;
      syntaxHighlighting = true;
      languages.enableFormat = true;
      treesitter.enable = true;
      treesitter.highlight.enable = true;
      treesitter.textobjects.enable = true;
      languages.go = {
        enable = true;
        format.type = "gofumpt";
        treesitter.enable = true;
      };
      languages.nix = {
        enable = true;
        extraDiagnostics.enable = true;
        format.enable = true;
        format.type = "nixfmt";
        treesitter.enable = true;
      };
    };
  };
}
