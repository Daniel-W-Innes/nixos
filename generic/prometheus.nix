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
    8080
    9558
    9633
  ];
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    openFirewall = true;
    firewallFilter = "-i br0 -p tcp -m tcp --dport 9100";
  };
  virtualisation.oci-containers.containers = {
    smartctl-exporter = {
      image = "prometheuscommunity/smartctl-exporter:latest";
      privileged = true;
      user = "root";
      ports = [
        "0.0.0.0:9633:9633/tcp"
      ];
    };
    cadvisor = {
      image = "gcr.io/cadvisor/cadvisor:latest";
      privileged = true;
      ports = [
        "0.0.0.0:9580:8080/tcp"
      ];
      volumes = [
        "/:/rootfs:ro"
        "/var/run:/var/run:ro"
        "/sys:/sys:ro"
        "/var/lib/containers:/var/lib/containers:ro"
      ];
    };
    systemd-exporter = {
      image = "quay.io/prometheuscommunity/systemd-exporter:latest";
      ports = [
        "0.0.0.0:9558:9558/tcp"
      ];
      volumes = [
        "/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket:ro"
      ];
    };
  };
}
