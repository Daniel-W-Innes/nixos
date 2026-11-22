{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.openvpn-exporter;
  exporter = pkgs.buildGoModule {
    pname = "openvpn-exporter";
    version = "0.1.0";
    src = ./openvpn-exporter;
    # Stdlib-only (no deps to vendor).
    vendorHash = null;
    meta.mainProgram = "openvpn-exporter";
  };
in
{
  options.services.openvpn-exporter = {
    enable = lib.mkEnableOption "Prometheus exporter for the OpenVPN --status file";

    statusPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/openvpn/pia.status";
      description = "Path to the OpenVPN --status file to export.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:9176";
      description = "Listen address for the exporter.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.openvpn-exporter = {
      description = "OpenVPN status exporter";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe exporter} -status-path ${cfg.statusPath} -listen ${cfg.listenAddress}";
        Restart = "on-failure";
        DynamicUser = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        CapabilityBoundingSet = [ ];
        AmbientCapabilities = [ ];
        SystemCallArchitectures = "native";
      };
    };
  };
}
