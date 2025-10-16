{ nixpkgs, ... }:

{
  programs.nvf = {
    enable = true;
    settings.vim = {
      viAlias = false;
      vimAlias = true;
      languages.enableFormat = true;
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
