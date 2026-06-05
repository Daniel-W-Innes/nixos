let
  danielAtOnion = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPOhOXM61fK+PiqPSD8eZ+cW0ACcl8IeBJO14odVsmVU";
  danielAtMelon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID8N4zSVA9MvNfdBlloRyFCazPH09qlkyCZ+6xTe2Cce";
  danielAtCucamelon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGsC8nOkFrvAzgNU/B2LE4ETtioDii+i/P1lV+ksWl6P";
  users = [
    danielAtOnion
    danielAtMelon
    danielAtCucamelon
  ];

  melon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGfXv9Rj3ehko7lxuR5FEVfp6muQgeVD3s9O5SP3JHDk";
  onion = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIBpuKeJyjChW46/PGlgXdvAV/suVKaDkWbPEV7SzDDt";
  cucamelon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP3kSQXEiRArrxyhSp27n2pIRUbxS0khtn4zI/y3kgna";
  systems = [
    melon
    onion
    cucamelon
  ];
in
{
  "wifi.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "user-daniel.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "copyparty-metrics.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "qbittorrent-webui-password.env.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "grafana-admin-password.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "grafana-secret-key.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "unpoller-password.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "pumpkin-smb-credentials.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "traefik-env.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "transmission.credentialsFile.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "proton-vpn.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "meilisearch-masterKey.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "searx-metrics-password.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "searx-key.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "searx-daniel-token.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "airzone-exporter.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "sonarr-api-key.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "radarr-api-key.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "lidarr-api-key.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "prowlarr-api-key.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "openweathermap-api-key.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "openweathermap-coords.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "influxdb-admin-password.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "influxdb-admin-token.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "influxdb-visibility-token-read.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
  "konnected-influxdb-token.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
}
