_:

{
  services.calibre-web = {
    enable = true;
    openFirewall = true;
    group = "media";
    listen.ip = "0.0.0.0";
    options = {
      calibreLibrary = "/mnt/references";
      enableBookConversion = true;
      enableBookUploading = true;
    };
  };
}
