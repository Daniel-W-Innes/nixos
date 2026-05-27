{ config, secretsDir, ... }:

{
  age.secrets.openweathermap-api-key = {
    file = secretsDir + "/openweathermap-api-key.age";
    owner = "root";
    group = "root";
    mode = "0400";
  };

  age.secrets.openweathermap-coords = {
    file = secretsDir + "/openweathermap-coords.age";
    owner = "root";
    group = "root";
    mode = "0400";
  };

  services.prometheus.exporters.openweathermap = {
    enable = true;
    apiKeyFile = config.age.secrets.openweathermap-api-key.path;
    coordsFile = config.age.secrets.openweathermap-coords.path;
    refreshInterval = "2m";
  };
}