_:

{
  users.users.calibre = {
    shell = "/run/current-system/sw/bin/nologin";
    isNormalUser = false;
    extraGroups = [ "nas" ];
  };
  services.calibre-web = {
    enable = true;
    user = "calibre";
    options = {
      enableBookUploading = true;
    };
  };
}
