{ ... }:

{
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    openFirewall = true;
    firewallFilter = "-i br0 -p tcp -m tcp --dport 9100";
  };
}
