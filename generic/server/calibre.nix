_:

{
  services.calibre-web = {
    enable = true;
    group = "media";
    options = {
      calibreLibrary = "/mnt/references";
      enableBookConversion = true;
      enableBookUploading = true;
    };
  };
}
