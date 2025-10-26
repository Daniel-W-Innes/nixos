{ pkgs, ... }:

{
  home.packages = with pkgs; [
    nh
  ];

  programs = {
    git = {
      enable = true;
      userName = "Daniel Innes";
      userEmail = "daniel@brotherwolf.ca";
      config = {
        push = { autoSetupRemote = true; };
      };
    };

    starship = {
      enable = true;
      settings = {
        add_newline = false;
        aws.disabled = true;
        gcloud.disabled = true;
        line_break.disabled = true;
      };
    };

    zsh = {
      enable = true;
      enableCompletion = true;
      syntaxHighlighting.enable = true;
      oh-my-zsh = {
        enable = true;
        plugins = [
          "git"
          "starship"
          "sudo"
          "ssh-agent"
          "podman"
          "gh"
        ];
        theme = "random";
      };
    };
  };
}
