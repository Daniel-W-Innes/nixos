{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.porla;

  package = pkgs.stdenvNoCC.mkDerivation {
    pname = "porla";
    version = "0.55.1";

    # Official release binary: fully static (musl, static-pie), the same
    # build that ships in the Docker image, so it runs as-is on NixOS.
    src = pkgs.fetchurl {
      url = "https://github.com/porla/porla/releases/download/v0.55.1/porla-linux-amd64";
      hash = "sha256-eufLRULMhcFnFGPJjLMagextzLJYUSKiIA7HxoJbYeQ=";
    };

    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      install -Dm755 $src $out/bin/porla
    '';

    meta = {
      description = "A high performance BitTorrent client for servers and seedboxes";
      homepage = "https://porla.org";
      license = lib.licenses.mit;
      mainProgram = "porla";
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  options.services.porla = {
    enable = lib.mkEnableOption "porla BitTorrent client";

    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      description = "The porla package to run.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/porla";
      description = "Directory porla stores its state in (`PORLA_STATE_DIR`).";
    };

    httpHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address the web interface listens on (`PORLA_HTTP_HOST`).";
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 1337;
      description = "Port the web interface listens on (`PORLA_HTTP_PORT`).";
    };

    allowedHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Hostnames allowed to access the web interface
        (`PORLA_HTTP_ALLOWED_HOSTS`). Only enforced when listening on
        127.0.0.1, but set it anyway when behind a reverse proxy.
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "trace"
        "debug"
        "info"
        "warning"
        "error"
        "fatal"
      ];
      default = "info";
      description = "Minimum log level (`PORLA_LOG_LEVEL`).";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "porla";
      description = "User the service runs as. Must not exist elsewhere in the configuration.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = ''
        Primary group of the service user. Downloads and state files are
        written with this group, so it should match the shared media group.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.porla = {
      description = "Porla BitTorrent client";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        PORLA_STATE_DIR = cfg.stateDir;
        PORLA_HTTP_HOST = cfg.httpHost;
        PORLA_HTTP_PORT = toString cfg.httpPort;
        PORLA_LOG_LEVEL = cfg.logLevel;
      }
      // lib.optionalAttrs (cfg.allowedHosts != [ ]) {
        PORLA_HTTP_ALLOWED_HOSTS = lib.concatStringsSep "," cfg.allowedHosts;
      };

      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        User = cfg.user;
        Group = cfg.group;
        # No sd_notify support, so a startup wedge can't trigger the start
        # timeout the way transmission's Type=notify did (2026-09-18); a
        # crash-loop restart still self-heals once the network path recovers.
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
      };
    };
  };
}
