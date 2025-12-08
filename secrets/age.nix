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

    copyparty-daniel = {
      file = ./copyparty-daniel.age;
      owner = "copyparty";
      group = "copyparty";
    };

    copyparty-metrics = {
      file = ./copyparty-metrics.age;
      owner = "copyparty";
      group = "copyparty";
    };

    prom-copyparty-metrics = {
      file = ./copyparty-metrics.age;
      owner = "prometheus";
      group = "prometheus";
    };
  };
}
