{ lib, config, ... }:

{
  services = {
    prometheus.exporters = {
      node = {
        enable = true;
        port = 9100;
        openFirewall = true;
        firewallFilter = "-i enp8s0 -p tcp -m tcp --dport 9100";
      };
      process = {
        enable = true;
        port = 9256;
        openFirewall = true;
        firewallFilter = "-i enp8s0 -p tcp -m tcp --dport 9256";
      };
      smartctl = lib.mkIf config.services.smartd.enable {
        enable = true;
        port = 9633;
        openFirewall = true;
        firewallFilter = "-i enp8s0 -p tcp -m tcp --dport 9633";
      };
      nvidia-gpu = lib.mkIf config.hardware.graphics.enable {
        enable = true;
        port = 9835;
        openFirewall = true;
        firewallFilter = "-i enp8s0 -p tcp -m tcp --dport 9835";
      };
    };
  };
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
    "avahi/services/smartctl-exporter.service" = lib.mkIf config.services.prometheus.exporters.smartctl.enable {
    text = ''<?xml version="1.0" standalone='no'?>
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
    };
    "avahi/services/process-exporter.service".text = ''<?xml version="1.0" standalone='no'?>
    <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">Process Exporter on %h</name>
      <service>
        <type>_http._tcp</type>
        <subtype>_process-exporter._sub._http._tcp</subtype>
        <port>9256</port>
        <txt-record>path=/metrics</txt-record>
      </service>
    </service-group>
    '';
    "avahi/services/nvidia-gpu-exporter.service" = lib.mkIf config.services.prometheus.exporters.nvidia-gpu.enable {
    text = ''<?xml version="1.0" standalone='no'?>
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">Nvidia-gpu Exporter on %h</name>
        <service>
          <type>_http._tcp</type>
          <subtype>_nvidia-gpu._sub._http._tcp</subtype>
          <port>9835</port>
          <txt-record>path=/metrics</txt-record>
        </service>
      </service-group>
      '';
    };
  };
}
