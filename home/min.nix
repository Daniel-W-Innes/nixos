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
      shellAliases = {
        nixr = "nh os switch -a github:Daniel-W-Innes/nixos";
      };
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
