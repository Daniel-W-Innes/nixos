let
  danielAtCucamelon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj7eEivrU4ow1BNNimeqqdTrvvs3S/NBqmqFPF6jnQu";
  danielAtOnion = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIPYmrcC2u9UBj5i9l7aPu7AJJRto0+0jBbDc3TXzUSv";
  users = [ danielAtCucamelon danielAtOnion ];

  systems = [ ];
in
{
  "yourspotify.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
}
