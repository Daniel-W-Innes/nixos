{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.prometheus.exporters.rtorrent;

  package = pkgs.buildGoModule {
    pname = "rtorrent-exporter";
    version = "0.1.0";
    src = pkgs.fetchgit {
      url = "https://github.com/victorjacobs/rtorrent-exporter";
      rev = "9706a204940ba6d76e0709e9d58108e4fe3fca60";
      hash = "sha256-/yMcH+zyxCHcPi9J4ORRBJtCLDSZjg0H8rDBmrYStpQ=";
    };
    vendorHash = "sha256-f0f8tYmoI6DtuB/K4++gu9b2na/d0ECTaF2zvDijW58=";
    ldflags = [
      "-s"
      "-w"
      "-X main.version=0.1.0"
    ];
    meta = {
      description = "Prometheus exporter for rTorrent's SCGI/XML-RPC Unix socket";
      homepage = "https://github.com/victorjacobs/rtorrent-exporter";
      license = lib.licenses.mit;
      mainProgram = "rtorrent-exporter";
    };
  };
in
{
  options.services.prometheus.exporters.rtorrent = {
    enable = lib.mkEnableOption "rTorrent Prometheus exporter";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to bind the exporter to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9135;
      description = "Port to bind the exporter to.";
    };

    socket = lib.mkOption {
      type = lib.types.path;
      default = "/run/rtorrent/rpc.sock";
      description = "Path to the rTorrent SCGI Unix socket to scrape.";
    };

    socketGroup = lib.mkOption {
      type = lib.types.str;
      default = "rtorrent";
      description = "Group allowed to access the rTorrent Unix socket (added as a supplementary group).";
    };

    timeout = lib.mkOption {
      type = lib.types.str;
      default = "5s";
      description = "Timeout for each rTorrent scrape, as a Go duration.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.prometheus-rtorrent-exporter = {
      description = "rTorrent Prometheus exporter";
      after = [
        "network.target"
        "rtorrent.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        DynamicUser = true;
        SupplementaryGroups = [ cfg.socketGroup ];
        ExecStart = lib.escapeShellArgs [
          "${package}/bin/rtorrent-exporter"
          "-web.listen-address=${cfg.listenAddress}:${toString cfg.port}"
          "-rtorrent.socket=${toString cfg.socket}"
          "-rtorrent.timeout=${cfg.timeout}"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
      };
    };
  };
}
