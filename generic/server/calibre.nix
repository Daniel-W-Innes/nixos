_:

{
  services.calibre-server = {
    enable = true;
    group = "media";
    libraries = [
      "/mnt/references"
    ];
    extraFlags = [
      "--daemonize"
    ];
  };
}
