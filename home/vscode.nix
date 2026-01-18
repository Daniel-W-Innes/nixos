_:

{
  programs.vscode = {
    enable = true;
    profiles.default.userSettings = {
      "editor.fontFamily" = "'Jetbrains Mono Nerd Font'; 'monospace'; monospace";
      "editor.formatOnSave" = true;
      "editor.inlineSuggest.enabled" = true;
      "merge-conflict.autoNavigateNextConflict.enabled" = true;
    };
  };
}
