_:

{
  age.secrets = {
    wifi = {
      file = ./wifi.age;
      owner = "root";
      group = "root";
    };

    user-daniel = {
      file = ./user-daniel.age;
      owner = "root";
      group = "root";
    };

    # copyparty-daniel = {
    #   file = ./copyparty-daniel.age;
    #   owner = "copyparty";
    #   group = "copyparty";
    # };

    # copyparty-metrics = {
    #   file = ./copyparty-metrics.age;
    #   owner = "copyparty";
    #   group = "copyparty";
    # };

    # prom-copyparty-metrics = {
    #   file = ./copyparty-metrics.age;
    #   owner = "prometheus";
    #   group = "prometheus";
    # };

    # grafana-admin-password = {
    #   file = ./grafana-admin-password.age;
    #   owner = "grafana";
    #   group = "grafana";
    #   mode = "0400";
    # };

    gluetun-wireguard = {
      file = ./gluetun-wireguard.env.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    qbittorrent-webui-password-pbkdf2 = {
      file = ./qbittorrent-webui-password-pbkdf2.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    qbittorrent-webui-password = {
      file = ./qbittorrent-webui-password.env.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };
}
