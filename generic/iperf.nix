_:

{
  environment.etc."avahi/services/iperf3.service".text = ''<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Iperf3 on %h</name>
  <service>
    <type>_http._tcp</type>
    <subtype>_iperf3._sub._http._tcp</subtype>
    <port>5201</port>
  </service>
</service-group>
'';
  services.iperf3 = {
    enable = true;
    openFirewall = true;
    port = 5201;
  };
}
