{ config, secretsDir, ... }:

{
  users.groups.meilisearch = { };
  users.users.meilisearch = {
    isSystemUser = true;
    group = "meilisearch";
  };
  age.secrets.meilisearch-masterKey = {
    file = secretsDir + /meilisearch-masterKey.age;
    owner = "meilisearch";
    group = "meilisearch";
    mode = "0400";
  };

  services.meilisearch = {
    enable = true;
    masterKeyFile = config.age.secrets.meilisearch-masterKey.path;
    settings = {
      no_analytics = false;
      env = "production";
    };
  };
  virtualisation.oci-containers.containers = {
    meilisearch-ui = {
      image = "eyeix/meilisearch-ui:latest";
      ports = [
        "127.0.0.1:24900:24900/tcp"
      ];
    };
  };
}
