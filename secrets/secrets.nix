let
  danielAtCucamelon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj7eEivrU4ow1BNNimeqqdTrvvs3S/NBqmqFPF6jnQu";
  users = [ danielAtCucamelon ];

  systems = [ ];
in
{
  "wifi.age" = {
    publicKeys = users ++ systems;
    armor = true;
  };
}
