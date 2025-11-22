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
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        add_newline = false;
        aws.disabled = true;
        gcloud.disabled = true;
        line_break.disabled = true;
      };
    };

    zoxide = {
      enable = true;
      enableZshIntegration = true;
      options = [ "--cmd cd" ];
    };

    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      history.append = true;
      history.save = 1000000;
      history.expireDuplicatesFirst = true;
    };
  };
}
