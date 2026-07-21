_:

{
  programs = {
    vscode.enable = true;
    go = {
      enable = true;
      telemetry.mode = "on";
    };
    gcc.enable = true;
    gh = {
      enable = true;
      settings.git_protocol = "ssh";
    };
  };
}
