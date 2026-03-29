_:

{
  environment.etc = {
    "avahi/services/node-exporter.service".text = ''<?xml version="1.0" standalone='no'?>
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
    "avahi/services/smartctl-exporter.service".text = ''<?xml version="1.0" standalone='no'?>
    <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">Smartctl Exporter on %h</name>
      <service>
        <type>_http._tcp</type>
        <subtype>_smartctl-exporter._sub._http._tcp</subtype>
        <port>9633</port>
        <txt-record>path=/metrics</txt-record>
      </service>
    </service-group>
    '';
    "avahi/services/cadvisor.service".text = ''<?xml version="1.0" standalone='no'?>
    <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">cAdvisor on %h</name>
      <service>
        <type>_http._tcp</type>
        <subtype>_cadvisor._sub._http._tcp</subtype>
        <port>9580</port>
        <txt-record>path=/metrics</txt-record>
      </service>
    </service-group>
    '';
    "avahi/services/systemd-exporter.service".text = ''<?xml version="1.0" standalone='no'?>
    <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">Systemd Exporter on %h</name>
      <service>
        <type>_http._tcp</type>
        <subtype>_systemd-exporter._sub._http._tcp</subtype>
        <port>9558</port>
        <txt-record>path=/metrics</txt-record>
      </service>
    </service-group>
    '';
  };
  networking.firewall.interfaces."br0".allowedTCPPorts = [
    9580
  ];
  services = {
    prometheus.exporters = {
      node = {
        enable = true;
        port = 9100;
        openFirewall = true;
        firewallFilter = "-i br0 -p tcp -m tcp --dport 9100";
      };
      process = {
        enable = true;
        port = 9256;
        openFirewall = true;
        firewallFilter = "-i br0 -p tcp -m tcp --dport 9256";
      };
      smartctl = {
        enable = true;
        port = 9633;
        openFirewall = true;
        firewallFilter = "-i br0 -p tcp -m tcp --dport 9633";
      };
      nvidia-gpu = {
        enable = true;
        port = 9835;
        openFirewall = true;
        firewallFilter = "-i br0 -p tcp -m tcp --dport 9835";
      };
      # systemd = {
      #   enable = true;
      #   port = 9558;
      #   openFirewall = true;
      #   firewallFilter = "-i br0 -p tcp -m tcp --dport 9558";
      # };
      # borgmatic = {
      #   enable = true;
      #   port = 9996;
      #   openFirewall = true;
      #   user = "root";
      #   firewallFilter = "-i br0 -p tcp -m tcp --dport 9996";
      # };
    };
    cadvisor = {
      enable = true;
      port = 9580;
    };
  };
}
