{ pkgs, ... }:

{
  home.packages = with pkgs; [
    nh
  ];

  programs = {
    git = {
      enable = true;
      settings.user = {
        name = "Daniel Innes";
        email = "daniel@brotherwolf.ca";
      };
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

    eza = {
      enable = true;
      enableZshIntegration = true;
    };

    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      history = {
        append = true;
        save = 1000000;
        expireDuplicatesFirst = true;
      };
      shellAliases = {
        ls = "eza";
        l = "eza -lah --git";
        ll = "eza -lh";
        lt = "eza --tree";
        lx = "eza -lah";

        g = "git";
        ga = "git add";
        gc = "git commit";
        gca = "git commit --amend";
        gp = "git push";
        gpf = "git push --force-with-lease";
        gl = "git pull";
        gs = "git status -sb";
        gd = "git diff";
        glog = "git log --oneline --graph --decorate -20";
        gfr = "git fetch && git rebase $(git symbolic-ref refs/remotes/origin/HEAD --short)";

        n = "nh";
        ns = "nh os switch -a";
        nt = "nh os test --dry";
        nc = "nh clean all -a -k 5 -K 5days";

        mkdir = "mkdir -p";
      };
    };
  };
  services.ssh-agent.enable = true;
}
