{ pkgs, ... }:

{
  programs = {
    vscode = {
      enable = true;
      profiles.default = {
        userSettings = {
          "chat.agent.enabled" = false;
          "editor.inlineSuggest.enabled" = true;
          "merge-conflict.autoNavigateNextConflict.enabled" = true;
          "git.autofetch" = true;
          "git.confirmSync" = false;
          "git.suggestSmartCommit" = false;
          "harper.dialect" = "Canadian";
        };
        extensions = with pkgs.vscode-extensions; [
          # elijah-potter.harper removed for hash mismatch
          golang.go
          bbenoist.nix
        ];
      };
    };
    go = {
      enable = true;
      telemetry.mode = "on";
    };
    gcc.enable = true;
  };
}
