{ ... }:

{
  age.secrets.wifi = {
    file = ./wifi.age;
    owner = "root";
    group = "root";
  };

  age.secrets.user-daniel = {
    file = ./user-daniel.age;
    owner = "root";
    group = "root";
  };
}
