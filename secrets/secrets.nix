let
  danielAtOnion = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPOhOXM61fK+PiqPSD8eZ+cW0ACcl8IeBJO14odVsmVU";
  danielAtMelon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID8N4zSVA9MvNfdBlloRyFCazPH09qlkyCZ+6xTe2Cce";
  users = [
    danielAtOnion
    danielAtMelon
  ];

  melon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGfXv9Rj3ehko7lxuR5FEVfp6muQgeVD3s9O5SP3JHDk";
  onion = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIBpuKeJyjChW46/PGlgXdvAV/suVKaDkWbPEV7SzDDt";
  systems = [
    melon
    onion
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
  "openvpn.env.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
}
