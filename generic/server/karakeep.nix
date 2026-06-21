{ config, ...}:

{
  services.karakeep = {
    enable = true;
    extraEnvironment = {
      MEILI_ADDR = "https://meilisearch.lc.brotherwolf.ca";
      MEILI_MASTER_KEY_FILE = config.age.secrets.meilisearch-masterKey.path;
    };
  };
}
