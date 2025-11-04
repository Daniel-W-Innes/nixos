let
  danielAtOnion = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIPYmrcC2u9UBj5i9l7aPu7AJJRto0+0jBbDc3TXzUSv";
  users = [
    danielAtOnion
  ];

  cucamelon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMIUPc/wkbTHq5ZdkX6YzG3qrFchIF6TB2ikBNWGYrGq";
  onion = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIBpuKeJyjChW46/PGlgXdvAV/suVKaDkWbPEV7SzDDt";
  installer = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL+k0CO0KCBoMUs1Uh9DKM6kM0nRruwA8Ob+dgmKG1qU";
  systems = [
    cucamelon
    onion
    installer
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
}
