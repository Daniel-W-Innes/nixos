{ ... }:

{
  age.secrets.yourspotify = {
    file = ./yourspotify.nix;
    path = "config.age.secretsDir/yourspotify.env";
  };
}
