{ config, lib, ... }:

{
  services.displayManager.ly = {
    enable = true;
    settings = {
      bigclock = true;
      blank_password = true;
    };
    x11Support = false;
  };
  preservation.preserveAt."/preserve/host".directories =
    lib.mkIf config.services.displayManager.sddm.enable [ "/var/lib/sddm" ];
}
