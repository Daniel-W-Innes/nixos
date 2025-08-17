{ ... }:

{
  age = {
    identityPaths = [ "/home/daniel/.ssh/id_ed25519" ];
    secrets.yourspotify = {
      file = ./yourspotify.age;
      owner = "daniel";
      group = "users";
      mode = "400";
    };
  };
}
