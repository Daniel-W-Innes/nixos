{ config, lib, ...}:

{
  services.karakeep = {
    enable = true;
    extraEnvironment = {
      MEILI_ADDR = lib.mkForce "https://meilisearch.lc.brotherwolf.ca";
      MEILI_MASTER_KEY_FILE = lib.mkForce config.age.secrets.meilisearch-masterKey.path;
    };
  };
}
