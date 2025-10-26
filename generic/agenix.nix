{
  age.rekey = {
    masterIdentities = [ ./your-yubikey-identity.pub ];
    storageMode = "local";
    localStorageDir = ./. + "/secrets/rekeyed/${config.networking.hostName}";
  };
}
