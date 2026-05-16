_:

{
  systemd.tmpfiles.rules = [
    "d /var/log/calibre 0755 calibre-server media -"
  ];

  services.calibre-server = {
    enable = true;
    group = "media";
    port = 23155;
    libraries = [
      "/mnt/references"
    ];
    extraFlags = [
      "--daemonize"
      "--log=/var/log/calibre/calibre-server.log"
    ];
  };
}

