{ config, secretsDir, ... }:

{
  age.secrets.mosquitto-passwd = {
    file = secretsDir + "/mosquitto-passwd.age";
    mode = "0400";
    owner = "mosquitto";
    group = "mosquitto";
  };

  services.mosquitto = {
    enable = true;
    settings = {
      per_listener_settings = false;
      listener = [ { port = 1883; } ];

      password_file = config.age.secrets.mosquitto-passwd.path;
      allow_anonymous = false;

      prometheus = true;
      prometheus_port = 1884;
      prometheus_listen = "127.0.0.1";
      prometheus_metrics_path = "/metrics";
    };
  };
}
