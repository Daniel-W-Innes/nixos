{ config, lib, ...}:

{
  services.karakeep = {
    enable = true;
    extraEnvironment = lib.mkIf config.services.meilisearch.enable {
      MEILI_ADDR = "https://meilisearch.lc.brotherwolf.ca";
      MEILI_MASTER_KEY_FILE = config.age.secrets.meilisearch-masterKey.path;
    };
    meilisearch.enable = !config.services.meilisearch.enable;
  };
}
