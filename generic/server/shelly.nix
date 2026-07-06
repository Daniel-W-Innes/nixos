{
  config,
  lib,
  pkgs,
  secretsDir,
  ...
}:

let
  shellyProductsAndMetrics = {
    products = [
      {
        type = "SNPL-00116US";
        export = {
          isok = "isok";
          power = "data.device_status.switch:0.apower";
          current = "data.device_status.switch:0.current";
          voltage = "data.device_status.switch:0.voltage";
          total_energy = "data.device_status.switch:0.aenergy.total";
          temperature = "data.device_status.switch:0.temperature.tC";
          output = "data.device_status.switch:0.output";
          uptime = "data.device_status.sys.uptime";
          restart_required = "data.device_status.sys.restart_required";
          mac = "data.device_status.sys.mac";
          cloud_connected = "data.device_status.cloud.connected";
          wifi_rssi = "data.device_status.wifi.rssi";
          updated = "data.device_status._updated";
        };
        devices = [
          {
            id = "c049ef8c2df4";
            shelly_name = "Desktop";
            name = "Desktop";
          }
          {
            id = "c049ef8bc9a4";
            shelly_name = "Server";
            name = "Server";
          }
          {
            id = "c049ef89d63c";
            shelly_name = "Dehumidifier";
            name = "Dehumidifier";
          }
          {
            id = "c049ef8ae4c8";
            shelly_name = "Plug 4";
            name = "Plug 4";
          }
        ];
      }
      {
        type = "S3SN-0U12A";
        export = {
          isok = "isok";
          temperature = "data.device_status.temperature:0.tC";
          humidity = "data.device_status.humidity:0.rh";
          battery_percent = "data.device_status.devicepower:0.battery.percent";
          battery_voltage = "data.device_status.devicepower:0.battery.V";
          wakeup_period = "data.device_status.sys.wakeup_period";
          restart_required = "data.device_status.sys.restart_required";
          mac = "data.device_status.sys.mac";
          cloud_connected = "data.device_status.cloud.connected";
          sleeping = "data.device_status._sleeping";
          updated = "data.device_status._updated";
        };
        devices = [
          {
            id = "543204670dc4";
            shelly_name = "Bedroom";
            name = "Bedroom";
          }
          {
            id = "dcda0ce1ef04";
            shelly_name = "Living Room";
            name = "Living Room";
          }
        ];
      }
      {
        type = "SNSN-0013A";
        export = {
          isok = "isok";
          temperature = "data.device_status.temperature:0.tC";
          humidity = "data.device_status.humidity:0.rh";
          battery_percent = "data.device_status.devicepower:0.battery.percent";
          battery_voltage = "data.device_status.devicepower:0.battery.V";
          wakeup_period = "data.device_status.sys.wakeup_period";
          restart_required = "data.device_status.sys.restart_required";
          mac = "data.device_status.sys.mac";
          cloud_connected = "data.device_status.cloud.connected";
          sleeping = "data.device_status._sleeping";
          updated = "data.device_status._updated";
        };
        devices = [
          {
            id = "c049ef8af210";
            shelly_name = "Office";
            name = "Office";
          }
        ];
      }
      {
        type = "shellyuni";
        export = {
          isok = "isok";
          has_update = "data.device_status.has_update";
          uptime = "data.device_status.uptime";
          cloud_connected = "data.device_status.cloud.connected";
          mac = "data.device_status.mac";
          wifi_rssi = "data.device_status.wifi_sta.rssi";
          relay0_ison = "data.device_status.relays.0.ison";
          relay1_ison = "data.device_status.relays.1.ison";
          ram_free = "data.device_status.ram_free";
          ram_total = "data.device_status.ram_total";
          ext_temp0 = "data.device_status.ext_temperature.0.tC";
          ext_temp1 = "data.device_status.ext_temperature.1.tC";
          updated = "data.device_status._updated";
        };
        devices = [
          {
            id = "c8c9a31b5ec5";
            shelly_name = "HVAC";
            name = "HVAC";
          }
        ];
      }
    ];
    metrics = [
      {
        type = "SNPL-00116US";
        fqname = "shelly_plug_info";
        help = "Non-numeric data, value is always 1";
        labels = [
          "shelly_name"
          "name"
          "isok"
          "power"
          "current"
          "voltage"
          "total_energy"
          "temperature"
          "output"
          "uptime"
          "restart_required"
          "mac"
          "cloud_connected"
          "wifi_rssi"
          "updated"
        ];
      }
      {
        type = "SNPL-00116US";
        fqname = "shelly_plug_power_watts";
        help = "Power (W)";
        resultKey = "power";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNPL-00116US";
        fqname = "shelly_plug_current_amps";
        help = "Current (A)";
        resultKey = "current";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNPL-00116US";
        fqname = "shelly_plug_voltage_volts";
        help = "Voltage (V)";
        resultKey = "voltage";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNPL-00116US";
        fqname = "shelly_plug_energy_watthours";
        help = "Total energy (Wh)";
        resultKey = "total_energy";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNPL-00116US";
        fqname = "shelly_plug_temperature_celsius";
        help = "Temperature (C)";
        resultKey = "temperature";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNPL-00116US";
        fqname = "shelly_plug_output";
        help = "Switch output state";
        resultKey = "output";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNPL-00116US";
        fqname = "shelly_plug_uptime_seconds";
        help = "Uptime (s)";
        resultKey = "uptime";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNPL-00116US";
        fqname = "shelly_plug_restart_required";
        help = "Restart required";
        resultKey = "restart_required";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNPL-00116US";
        fqname = "shelly_plug_cloud_connected";
        help = "Cloud connected";
        resultKey = "cloud_connected";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNPL-00116US";
        fqname = "shelly_plug_wifi_rssi";
        help = "WiFi RSSI (dBm)";
        resultKey = "wifi_rssi";
        labels = [
          "shelly_name"
          "name"
        ];
      }

      {
        type = "S3SN-0U12A";
        fqname = "shelly_htg3_info";
        help = "Non-numeric data, value is always 1";
        labels = [
          "shelly_name"
          "name"
          "isok"
          "temperature"
          "humidity"
          "battery_percent"
          "battery_voltage"
          "wakeup_period"
          "restart_required"
          "mac"
          "cloud_connected"
          "sleeping"
          "updated"
        ];
      }
      {
        type = "S3SN-0U12A";
        fqname = "shelly_htg3_temperature_celsius";
        help = "Temperature (C)";
        resultKey = "temperature";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "S3SN-0U12A";
        fqname = "shelly_htg3_humidity_percent";
        help = "Humidity (%RH)";
        resultKey = "humidity";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "S3SN-0U12A";
        fqname = "shelly_htg3_battery_percent";
        help = "Battery (%)";
        resultKey = "battery_percent";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "S3SN-0U12A";
        fqname = "shelly_htg3_battery_voltage";
        help = "Battery voltage (V)";
        resultKey = "battery_voltage";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "S3SN-0U12A";
        fqname = "shelly_htg3_wakeup_period";
        help = "Wakeup period (s)";
        resultKey = "wakeup_period";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "S3SN-0U12A";
        fqname = "shelly_htg3_cloud_connected";
        help = "Cloud connected";
        resultKey = "cloud_connected";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "S3SN-0U12A";
        fqname = "shelly_htg3_sleeping";
        help = "Sleeping state";
        resultKey = "sleeping";
        labels = [
          "shelly_name"
          "name"
        ];
      }

      {
        type = "SNSN-0013A";
        fqname = "shelly_plussht_info";
        help = "Non-numeric data, value is always 1";
        labels = [
          "shelly_name"
          "name"
          "isok"
          "temperature"
          "humidity"
          "battery_percent"
          "battery_voltage"
          "wakeup_period"
          "restart_required"
          "mac"
          "cloud_connected"
          "sleeping"
          "updated"
        ];
      }
      {
        type = "SNSN-0013A";
        fqname = "shelly_plussht_temperature_celsius";
        help = "Temperature (C)";
        resultKey = "temperature";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNSN-0013A";
        fqname = "shelly_plussht_humidity_percent";
        help = "Humidity (%RH)";
        resultKey = "humidity";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNSN-0013A";
        fqname = "shelly_plussht_battery_percent";
        help = "Battery (%)";
        resultKey = "battery_percent";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNSN-0013A";
        fqname = "shelly_plussht_battery_voltage";
        help = "Battery voltage (V)";
        resultKey = "battery_voltage";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNSN-0013A";
        fqname = "shelly_plussht_wakeup_period";
        help = "Wakeup period (s)";
        resultKey = "wakeup_period";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNSN-0013A";
        fqname = "shelly_plussht_cloud_connected";
        help = "Cloud connected";
        resultKey = "cloud_connected";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "SNSN-0013A";
        fqname = "shelly_plussht_sleeping";
        help = "Sleeping state";
        resultKey = "sleeping";
        labels = [
          "shelly_name"
          "name"
        ];
      }

      {
        type = "shellyuni";
        fqname = "shelly_uni_info";
        help = "Non-numeric data, value is always 1";
        labels = [
          "shelly_name"
          "name"
          "isok"
          "has_update"
          "uptime"
          "cloud_connected"
          "mac"
          "wifi_rssi"
          "relay0_ison"
          "relay1_ison"
          "ram_free"
          "ram_total"
          "ext_temp0"
          "ext_temp1"
          "updated"
        ];
      }
      {
        type = "shellyuni";
        fqname = "shelly_uni_has_update";
        help = "Has firmware update";
        resultKey = "has_update";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "shellyuni";
        fqname = "shelly_uni_uptime_seconds";
        help = "Uptime (s)";
        resultKey = "uptime";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "shellyuni";
        fqname = "shelly_uni_cloud_connected";
        help = "Cloud connected";
        resultKey = "cloud_connected";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "shellyuni";
        fqname = "shelly_uni_wifi_rssi";
        help = "WiFi RSSI (dBm)";
        resultKey = "wifi_rssi";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "shellyuni";
        fqname = "shelly_uni_ram_free";
        help = "Free RAM (bytes)";
        resultKey = "ram_free";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "shellyuni";
        fqname = "shelly_uni_ram_total";
        help = "Total RAM (bytes)";
        resultKey = "ram_total";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "shellyuni";
        fqname = "shelly_uni_relay0";
        help = "Relay 0 state";
        resultKey = "relay0_ison";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "shellyuni";
        fqname = "shelly_uni_relay1";
        help = "Relay 1 state";
        resultKey = "relay1_ison";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "shellyuni";
        fqname = "shelly_uni_ext_temp0_celsius";
        help = "Ext sensor 0 temperature (C)";
        resultKey = "ext_temp0";
        labels = [
          "shelly_name"
          "name"
        ];
      }
      {
        type = "shellyuni";
        fqname = "shelly_uni_ext_temp1_celsius";
        help = "Ext sensor 1 temperature (C)";
        resultKey = "ext_temp1";
        labels = [
          "shelly_name"
          "name"
        ];
      }
    ];
  };
  shellyProductsMetricsFile = pkgs.writeText "shelly-products-metrics.json" (
    builtins.toJSON shellyProductsAndMetrics
  );
in
{
  age.secrets.shelly-metrics = lib.mkIf config.services.prometheus.exporters.shelly.enable {
    file = secretsDir + /shelly-metrics.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };
  services.prometheus.exporters.shelly = {
    enable = true;
    port = 9882;
    metrics-file = "/run/prometheus-shelly-exporter/shelly-metrics-combined.json";
  };
  systemd.services.prometheus-shelly-exporter =
    lib.mkIf config.services.prometheus.exporters.shelly.enable
      {
        serviceConfig = {
          LoadCredential = [
            "shelly-account:${config.age.secrets.shelly-metrics.path}"
          ];
          RuntimeDirectory = "prometheus-shelly-exporter";
          RuntimeDirectoryMode = "0700";
          ExecStartPre = [
            "${pkgs.jq}/bin/jq -s '.[0] * .[1]' \
          \"/run/credentials/prometheus-shelly-exporter.service/shelly-account\" \
          ${shellyProductsMetricsFile} \
          > /run/prometheus-shelly-exporter/shelly-metrics-combined.json"
          ];
        };
      };
}
