{
  config,
  lib,
  pkgs,
  akvorado,
  ...
}:

with lib;

let
  cfg = config.services.akvorado;
in
{
  options.services.akvorado = {
    enable = mkEnableOption "Akvorado backend and frontend";

    backend = {
      enable = mkEnableOption "Akvorado backend" // {
        default = true;
      };
      port = mkOption {
        type = types.port;
        default = 8000;
        description = "Port for the backend service";
      };
      package = mkOption {
        type = types.package;
        default = akvorado.packages.${pkgs.system}.backend;
        description = "Akvorado backend package";
      };
      binaryName = mkOption {
        type = types.str;
        default = "akvorado";
        description = "Name of the backend binary";
      };
      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra arguments to pass to the backend";
      };
    };

    frontend = {
      enable = mkEnableOption "Akvorado frontend" // {
        default = true;
      };
      port = mkOption {
        type = types.port;
        default = 3000;
        description = "Port for the frontend service";
      };
      package = mkOption {
        type = types.package;
        default = akvorado.packages.${pkgs.system}.frontend;
        description = "Akvorado frontend package";
      };
      serverType = mkOption {
        type = types.enum [
          "python"
          "simple-http-server"
        ];
        default = "python";
        description = "HTTP server to use for serving frontend files";
      };
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/akvorado";
      description = "Directory for Akvorado state data";
    };
  };

  config = mkIf cfg.enable {
    systemd = {
      tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 root root -"
      ];
      services = {
        akvorado-backend = mkIf cfg.backend.enable {
          description = "Akvorado Backend - Network Traffic Analytics";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "simple";
            ExecStart = concatStringsSep " " (
              [ "${cfg.backend.package}/bin/${cfg.backend.binaryName}" ] ++ cfg.backend.extraArgs
            );
            Restart = "on-failure";
            RestartSec = 10;

            # Dynamic user
            DynamicUser = true;

            # Security hardening
            ProtectSystem = "strict";
            ProtectHome = true;
            NoNewPrivileges = true;
            PrivateNetwork = false;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];

            StateDirectory = "akvorado";
          };

          environment = {
            AKVORADO_DATA_DIR = cfg.dataDir;
            AKVORADO_PORT = toString cfg.backend.port;
          };
        };
        services.akvorado-frontend = mkIf cfg.frontend.enable {
          description = "Akvorado Frontend";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "simple";
            Restart = "on-failure";
            RestartSec = 10;

            # Dynamic user
            DynamicUser = true;

            ProtectSystem = "strict";
            ProtectHome = true;
            NoNewPrivileges = true;
            PrivateNetwork = false;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
          }
          // (
            if cfg.frontend.serverType == "python" then
              {
                ExecStart = concatStringsSep " " [
                  "${pkgs.python3}/bin/python3"
                  "-m http.server"
                  (toString cfg.frontend.port)
                  "--directory"
                  "${cfg.frontend.package}/share/akvorado-frontend"
                ];
              }
            else
              {
                ExecStart = concatStringsSep " " [
                  "${pkgs.simple-http-server}/bin/simple-http-server"
                  "-p"
                  (toString cfg.frontend.port)
                ];
                WorkingDirectory = "${cfg.frontend.package}/share/akvorado-frontend";
              }
          );
        };
      };
    };
    environment.systemPackages =
      (optional cfg.backend.enable cfg.backend.package)
      ++ (optional cfg.frontend.enable cfg.frontend.package)
      ++ (optional (
        cfg.frontend.enable && cfg.frontend.serverType == "simple-http-server"
      ) pkgs.simple-http-server);
  };

  meta.maintainers = [ ];
}
