_:

{
  environment.etc."avahi/services/node-exporter.service".text = ''<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Node Exporter on %h</name>
  <service>
    <type>_http._tcp</type>
    <subtype>_node-exporter._sub._http._tcp</subtype>
    <port>9100</port>
    <txt-record>path=/metrics</txt-record>
  </service>
</service-group>
'';
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    openFirewall = true;
    firewallFilter = "-i br0 -p tcp -m tcp --dport 9100";
  };
}
