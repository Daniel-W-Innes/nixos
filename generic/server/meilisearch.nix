{ config, secretsDir, ...}:

{ 
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
    };
  };
}