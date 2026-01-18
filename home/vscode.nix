_:

{
  programs.vscode = {
    enable = true;
    profiles.default.userSettings = {
      "workbench.colorTheme" = "IntelliJ IDEA Islands Dark";
      "chat.agent.enabled" = false;
      "editor.formatOnSave" = true;
      "editor.inlineSuggest.enabled" = true;
      "merge-conflict.autoNavigateNextConflict.enabled" = true;
      "git.autofetch" = true;
    };
  };
}
