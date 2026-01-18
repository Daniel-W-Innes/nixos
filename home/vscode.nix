_:

{
  programs.vscode = {
    enable = true;
    profiles.default.userSettings = {
      "editor.formatOnSave" = true;
      "editor.inlineSuggest.enabled" = true;
      "merge-conflict.autoNavigateNextConflict.enabled" = true;
    };
  };
}
