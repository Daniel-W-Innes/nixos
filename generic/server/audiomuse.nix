{
  config,
  lib,
  pkgs,
  secretsDir,
  ...
}:

let
  cfg = config.services.audiomuse;
  backend = config.virtualisation.oci-containers.backend;

  # Flask calls init_db() at import; supervisord gives up after 3 quick retries.
  # dependsOn orders starts but gives no readiness, so wait for accept() over
  # the loopback-published postgres port (uptime-kuma-mariadb pattern).
  waitForPostgres = pkgs.writeShellScript "audiomuse-wait-for-postgres" ''
    pg_isready="${lib.getExe' pkgs.postgresql "pg_isready"}"
    for _ in $(seq 1 90); do
      if "$pg_isready" -h 127.0.0.1 -p 5432 -U audiomuse -d audiomusedb -t 2 -q; then
        exit 0
      fi
      sleep 1
    done
    echo "timed out waiting for AudioMuse-AI PostgreSQL" >&2
    exit 1
  '';

  # The app containers reach postgres over audiomuse-net by container name
  # (aardvark DNS); the host publish on 127.0.0.1:5432 is only for the wait above.
  appEnvironment = {
    TZ = "America/Toronto";
    POSTGRES_USER = "audiomuse";
    POSTGRES_DB = "audiomusedb";
    POSTGRES_HOST = "audiomuse-postgres";
    POSTGRES_PORT = "5432";
    TEMP_DIR = "/app/temp_audio";
  };
in
{
  options.services.audiomuse = {
    enable = lib.mkEnableOption "AudioMuse-AI sonic-similarity service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      readOnly = true; # gunicorn bind is fixed in the image
      description = "AudioMuse-AI HTTP port.";
    };
  };

  config = lib.mkMerge [
    { services.audiomuse.enable = lib.mkDefault true; }
    (lib.mkIf cfg.enable {
      age.secrets.audiomuse-env = {
        file = secretsDir + /audiomuse-env.age;
        owner = "root";
        group = "root";
        mode = "0400";
      };

      systemd = {
        tmpfiles.rules = [
          "d /var/lib/audiomuse 0755 root root -"
          # postgres:15-alpine runs postgres as uid/gid 70 (999 is the Debian
          # image's uid); a wrong owner breaks the live data dir on every switch
          # (docs/issues/14-forgejo-tmpfiles-ownership-mismatch.md). No "Z" rule:
          # systemd refuses it with "unsafe path transition" — dead code there.
          "d /var/lib/audiomuse/postgres 0700 70 70 -"
          "d /var/lib/audiomuse/flask/temp-audio 0700 root root -"
          "d /var/lib/audiomuse/flask/plugins 0700 root root -"
          "d /var/lib/audiomuse/worker/temp-audio 0700 root root -"
          "d /var/lib/audiomuse/worker/plugins 0700 root root -"
        ];

        # Dedicated bridged network (bookorbit init-*-network pattern).
        # The flask and worker overrides are identical, so both are generated
        # from one expression (also keeps statix's repeated-key lint quiet).
        services = {
          init-audiomuse-network =
            let
              bin = if backend == "podman" then "${pkgs.podman}/bin/podman" else "${pkgs.docker}/bin/docker";
            in
            {
              description = "Create isolated AudioMuse-AI ${backend} Network";
              after = [ "${backend}.service" ];
              requires = [ "${backend}.service" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig.Type = "oneshot";
              script = ''
                ${bin} network inspect audiomuse-net >/dev/null 2>&1 || \
                ${bin} network create audiomuse-net
              '';
            };
        }
        //
          lib.genAttrs
            (map (name: "${backend}-audiomuse-${name}") [
              "flask"
              "worker"
            ])
            (_: {
              # dependsOn gives After/Requires only; upholds re-queues a
              # dependency-failed start job (forgejo outage precedent,
              # docs/reports/2026-09-27-forgejo-dependency-outage.md).
              # The module sets TimeoutStartSec=0, so the 90s wait is safe;
              # mkAfter appends after the module's own pre-start script.
              after = [ "init-audiomuse-network.service" ];
              requires = [ "init-audiomuse-network.service" ];
              upholds = [ "${backend}-audiomuse-postgres.service" ];
              serviceConfig.ExecStartPre = lib.mkAfter [ "${waitForPostgres}" ];
            });
      };

      virtualisation.oci-containers.containers = {
        audiomuse-postgres = {
          image = "postgres:15-alpine";
          environment = {
            TZ = "America/Toronto";
            POSTGRES_USER = "audiomuse";
            POSTGRES_DB = "audiomusedb";
          };
          environmentFiles = [ config.age.secrets.audiomuse-env.path ];
          volumes = [ "/var/lib/audiomuse/postgres:/var/lib/postgresql/data" ];
          # Loopback publish exists only for the host-side pg_isready wait (and
          # debugging); the app containers reach it over audiomuse-net.
          ports = [ "127.0.0.1:5432:5432" ];
          extraOptions = [
            "--network=audiomuse-net"
            # podman stop's 10s default SIGKILLs postgres mid fast-shutdown
            # (docs/issues/12-postgres-unclean-shutdown.md).
            "--stop-timeout=90"
          ];
        };

        audiomuse-flask = {
          image = "ghcr.io/neptunehub/audiomuse-ai:latest";
          dependsOn = [ "audiomuse-postgres" ];
          environment = appEnvironment // {
            SERVICE_TYPE = "flask";
          };
          environmentFiles = [ config.age.secrets.audiomuse-env.path ];
          ports = [ "127.0.0.1:${toString cfg.port}:8000" ];
          volumes = [
            "/var/lib/audiomuse/flask/temp-audio:/app/temp_audio"
            "/var/lib/audiomuse/flask/plugins:/app/plugin/installed"
          ];
          extraOptions = [ "--network=audiomuse-net" ];
        };

        audiomuse-worker = {
          image = "ghcr.io/neptunehub/audiomuse-ai:latest";
          dependsOn = [ "audiomuse-postgres" ];
          environment = appEnvironment // {
            SERVICE_TYPE = "worker";
          };
          environmentFiles = [ config.age.secrets.audiomuse-env.path ];
          volumes = [
            "/var/lib/audiomuse/worker/temp-audio:/app/temp_audio"
            "/var/lib/audiomuse/worker/plugins:/app/plugin/installed"
          ];
          extraOptions = [ "--network=audiomuse-net" ];
        };
      };
    })
  ];
}
