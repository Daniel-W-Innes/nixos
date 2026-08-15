{ config, lib, ... }:

{
  services.smartd.enable = true;
  preservation.preserveAt."/preserve/host".directories =
    lib.mkIf config.services.smartd.enable [ "/var/lib/smartmontools" ];
}
