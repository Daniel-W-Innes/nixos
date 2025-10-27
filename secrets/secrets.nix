let
  danielAtOnion = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIPYmrcC2u9UBj5i9l7aPu7AJJRto0+0jBbDc3TXzUSv";
  users = [ danielAtOnion ];

  cucamelon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMIUPc/wkbTHq5ZdkX6YzG3qrFchIF6TB2ikBNWGYrGq";
  onion = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIBpuKeJyjChW46/PGlgXdvAV/suVKaDkWbPEV7SzDDt";
  systems = [
    cucamelon
    onion
  ];
in
{
  "wifi.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
}
