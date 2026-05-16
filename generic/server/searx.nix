{ config, lib, secretsDir, ... }:

let
  settingsTemplate = ./searx/settings.yml;
  redisUrl = "unix://${config.services.redis.servers.searx.unixSocket}";
in
{
  age.secrets = {
    searx-key = lib.mkIf config.services.searx.enable {
      file = secretsDir + /searx-key.age;
      owner = "searx";
      group = "searx";
      mode = "0400";
    };
    searx-metrics-password = lib.mkIf config.services.searx.enable {
      file = secretsDir + /searx-metrics-password.age;
      owner = "searx";
      group = "searx";
      mode = "0400";
    };
  };

  services.searx = {
    enable = true;
    redisCreateLocally = true;
  };

  systemd.services.searx-init.script = lib.mkForce ''
    cd /run/searx

    (
      umask 077
      cp --no-preserve=mode ${settingsTemplate} settings.yml
    )

    secret_key="$(< ${config.age.secrets.searx-key.path})"
    metrics_password="$(< ${config.age.secrets.searx-metrics-password.path})"
    secret_key_escaped="$(printf '%s' "$secret_key" | sed -e 's/[\/&]/\\&/g')"
    metrics_password_escaped="$(printf '%s' "$metrics_password" | sed -e 's/[\/&]/\\&/g')"
    redis_url_escaped="$(printf '%s' '${redisUrl}' | sed -e 's/[\/&]/\\&/g')"

    sed \
      -e "s/@SEARX_SECRET_KEY@/$secret_key_escaped/g" \
      -e "s/@SEARX_METRICS_PASSWORD@/$metrics_password_escaped/g" \
      -e "s/@SEARX_REDIS_URL@/$redis_url_escaped/g" \
      -i settings.yml
  '';
}
