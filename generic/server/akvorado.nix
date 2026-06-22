_:

{
  services.akvorado = {
    enable = true;
    zookeeper = {
      listenHost = "https://zookeeper.lc.brotherwolf.ca";
    };
    clickhouse = {
      listenHost = "https://clickhouse.lc.brotherwolf.ca";
    };
    kafka = {
      listenHost = "https://kafka.lc.brotherwolf.ca";
      listenPort = 443;
    };
    console.port = 8980;
  };
}
