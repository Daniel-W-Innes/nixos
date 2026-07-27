{
  config,
  secretsDir,
  pkgs,
  ...
}:
{
  age.secrets.forgejo-runner-token = {
    file = secretsDir + /forgejo-runner-token.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances."${config.networking.hostName}" = {
      enable = true;
      name = "${config.networking.hostName}";
      tokenFile = config.age.secrets.forgejo-runner-token.path;
      url = "https://git.lc.brotherwolf.ca/";
      labels = [
        "golang:docker://docker.io/golang:1.26.5-alpine3.24"
        "alpine:docker://docker.io/alpine:3.24"
        "native:host"
        "${config.networking.hostName}:host"
      ];
    };
  };
}
