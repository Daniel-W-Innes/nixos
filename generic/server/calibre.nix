_:

{
  services.calibre-server = {
    enable = true;
    group = "media";
    port = 23155;
    libraries = [
      "/mnt/references"
    ];
    extraFlags = [
      "--daemonize"
      "--log=/var/log/calibre-server.log"
    ];
  };
}
