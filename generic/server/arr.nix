{
  config,
  lib,
  pkgs,
  secretsDir,
  ...
}:

let
  arrSettings = {
    enable = true;
    settings = {
      log.analyticsEnabled = true;
    };
  };

  transmissionSeedingCleanupScript = pkgs.writeShellScript "transmission-seeding-cleanup" ''
    RPC='http://192.168.15.1:9091/transmission/rpc'
    CREDS="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/transmission-rpc")"

    # List torrents and keep those that finished seeding (transmission's
    # ratio/idle limits only stop them) AND live under the FileFlows layout.
    # Pre-layout-change torrents (flat downloads/) are deliberately ignored.
    info="$(${pkgs.coreutils}/bin/timeout 30 ${pkgs.transmission_4}/bin/transmission-remote "$RPC" -n "$CREDS" -t all -i)"
    mapfile -t ids < <(
      ${pkgs.gawk}/bin/awk '
        /^  Id: / {
          if (state == "Finished" && loc ~ /^\/mnt\/media\/downloads\/complete(\/|$)/)
            print id
          id = $2
          state = ""
          loc = ""
          next
        }
        /^  State: / { state = substr($0, index($0, ":") + 2) }
        /^  Location: / { loc = substr($0, index($0, ":") + 2) }
        END {
          if (state == "Finished" && loc ~ /^\/mnt\/media\/downloads\/complete(\/|$)/)
            print id
        }
      ' <<<"$info"
    )

    for id in "''${ids[@]}"; do
      echo "removing finished-seeding torrent $id"
      ${pkgs.coreutils}/bin/timeout 30 ${pkgs.transmission_4}/bin/transmission-remote "$RPC" -n "$CREDS" -t "$id" --remove-and-delete
    done
  '';
in
{
  age.secrets = {
    transmission = lib.mkIf config.services.transmission.enable {
      file = secretsDir + /transmission.credentialsFile.age;
      owner = "transmission";
      group = "media";
      mode = "0400";
    };

    proton-vpn = lib.mkIf config.vpnNamespaces.proton.enable {
      file = secretsDir + /proton-vpn.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    fileflows-password = {
      file = secretsDir + /fileflows-password.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };

  fileSystems."/mnt/media" = {
    device = "//pumpkin.lc.brotherwolf.ca/Media";
    fsType = "cifs";
    options = [
      "credentials=${config.age.secrets.pumpkin-smb-credentials.path}"
      "x-systemd.automount"
      "noauto"
      "nofail"
      "uid=media"
      "gid=media"
      "file_mode=0660"
      "dir_mode=0770"
    ];
  };

  vpnNamespaces.proton = {
    enable = true;
    wireguardConfigFile = config.age.secrets.proton-vpn.path;
    accessibleFrom = [
      "10.8.8.0/24"
      "127.0.0.1/32"
    ];
    portMappings = [
      {
        from = 9091;
        to = 9091;
      }
      {
        from = 9586;
        to = 9586;
      }
    ];
    openVPNPorts = [
      {
        port = config.services.transmission.settings.peer-port;
        protocol = "both";
      }
    ];
  };

  systemd.services.transmission = {
    vpnConfinement = {
      enable = true;
      vpnNamespace = "proton";
    };

    # After an unclean power-off the daemon can wedge during startup (blocks
    # on the VPN data path before signalling READY) and systemd kills it
    # after TimeoutStartSec; with the default Restart=no the unit then stays
    # failed indefinitely (2026-09-18, docs/reports/2026-09-18-transmission-wedge.md).
    # Retry on failure so it self-heals once the tunnel path recovers.
    serviceConfig.Restart = "on-failure";

    # Startup loads ~4000 torrents synchronously and stats their files over
    # the pumpkin CIFS mount; the 90s default times out long before READY
    # (2026-09-18 incident). Same pattern as forgejo's TimeoutStartSec=600.
    serviceConfig.TimeoutStartSec = 600;

    # This is a hack to ensure the queue.json file exists before transmission starts, as it doesn't create it on its own and fails if it doesn't exist.
    serviceConfig.ExecStartPre = lib.mkAfter [
      (
        "+"
        + pkgs.writeShellScript "transmission-create-queue-json" ''
          queue_json='/var/lib/transmission/.config/transmission-daemon/queue.json'

          if [ ! -e "$queue_json" ]; then
            printf '[]\n' |
              install -D -m 600 -o transmission -g media /dev/stdin "$queue_json"
          fi
        ''
      )
    ];
  };

  systemd.services.prometheus-wireguard-exporter =
    lib.mkIf config.services.prometheus.exporters.wireguard.enable
      {
        vpnConfinement = {
          enable = true;
          vpnNamespace = "proton";
        };
      };

  services = {
    transmission = {
      enable = true;
      package = pkgs.transmission_4;
      credentialsFile = config.age.secrets.transmission.path;
      group = "media";
      settings = {
        message-level = 3;
        encryption = 1;
        download-dir = "/mnt/media/downloads/complete";
        incomplete-dir = "/mnt/media/downloads/incomplete";
        incomplete-dir-enabled = true;
        download-queue-enabled = false;
        rpc-bind-address = "192.168.15.1";
        rpc-whitelist = "192.168.15.5";
        rpc-whitelist-enabled = true;
        rpc-host-whitelist = "transmission.brotherwolf.ca,transmission.lc.brotherwolf.ca";
        lpd-enabled = true;
        peer-port = 51820;
        port-forwarding-enabled = true;
        idle_seeding_limit_enabled = true;
        idle_seeding_limit = 10080;
        ratio_limit = 5.0;
        ratio_limit_enabled = true;
      };
    };
    flaresolverr.enable = true;
    prowlarr = arrSettings;
    radarr = arrSettings;
    sonarr = arrSettings;
    lidarr = arrSettings;
    readarr = arrSettings;
    navidrome = {
      enable = true;
      group = "media";
      settings = {
        EnableInsightsCollector = true;
        MusicFolder = "/mnt/media/music";
        BaseUrl = "https://navidrome.lc.brotherwolf.ca";
        "Prometheus.Enabled" = true;
      };
    };
    jellyfin = {
      enable = true;
      group = "media";
    };
  };

  # ---- FileFlows: middleman between transmission and the *arrs -------------
  # No nixpkgs package exists, so this runs as an oci-container. It watches
  # /media/downloads/complete and flows relocate processed files to
  # /media/downloads/converted; the *arrs pick those up via Remote Path
  # Mappings. UI walkthrough: docs/fileflows.md.

  systemd.tmpfiles.rules = [
    "d /var/lib/fileflows 0770 media media -"
    "d /var/lib/fileflows/Data 0770 media media -"
    "d /var/lib/fileflows/Logs 0770 media media -"
    "d /var/lib/fileflows/temp 0770 media media -"
  ];

  virtualisation.oci-containers.containers.fileflows = {
    image = "revenz/fileflows:stable";
    environment = {
      TZ = "America/Toronto";
      # Match the media uid/gid (990/987, smb.nix) so files on the share are
      # written as media. The image creates its internal user from these.
      PUID = toString config.users.users.media.uid;
      PGID = toString config.users.groups.media.gid;
    };
    volumes = [
      "/var/lib/fileflows/Data:/app/Data"
      "/var/lib/fileflows/Logs:/app/Logs"
      "/var/lib/fileflows/temp:/temp" # scratch: local disk, never the CIFS share
      "/mnt/media/downloads:/media/downloads:rw"
    ];
    ports = [ "127.0.0.1:19200:5000/tcp" ];
  };

  # /mnt/media is an x-systemd.automount CIFS mount. If the automount does not
  # fire (pumpkin down at boot), a lookup under /mnt/media silently resolves to
  # the local root filesystem and podman would bind an empty local dir — the
  # container would process nothing and write output to the wrong disk.
  # Requiring the mount unit turns that into a loud start failure. (Safe: no
  # x-systemd.idle-timeout, so nothing stops the mount while the container runs.)
  systemd.services."${config.virtualisation.oci-containers.backend}-fileflows" = {
    after = [ "mnt-media.mount" ];
    requires = [ "mnt-media.mount" ];
  };

  # converted/ must exist on the share before FileFlows flows can write to it.
  # tmpfiles can't do this: /mnt/media is an x-systemd.automount CIFS mount, so
  # at boot (when tmpfiles runs) the share isn't mounted and the rule would
  # create the dir on the local root fs, shadowed once the share mounts. This
  # oneshot instead lets mkdir trigger the automount itself — if pumpkin is
  # down, the mkdir fails and the unit retries every 30s until the share is up.
  systemd.services.fileflows-converted-dir = {
    description = "Create /mnt/media/downloads/converted for FileFlows";
    after = [ "mnt-media.automount" ];
    requires = [ "mnt-media.automount" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "30s";
    };
    script = ''
      ${pkgs.coreutils}/bin/mkdir -p /mnt/media/downloads/converted
    '';
  };

  # transmission's ratio/idle limits only STOP a finished seeder — the files
  # stay in complete/ forever and the copy-flavour FileFlows flow never
  # reclaims them. This daily timer deletes such torrents via transmission
  # itself (--remove-and-delete), so seeding always runs its full course.
  systemd.services.transmission-seeding-cleanup = {
    description = "Remove finished-seeding torrents from transmission";
    after = [ "transmission.service" ];
    wants = [ "transmission.service" ];
    serviceConfig = {
      Type = "oneshot";
      LoadCredential = "transmission-rpc:${config.age.secrets.transmission.path}";
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
    script = "${transmissionSeedingCleanupScript}";
  };

  systemd.timers.transmission-seeding-cleanup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = 300;
      Persistent = true;
    };
  };

  systemd.services.traefik-fileflows-htpasswd = {
    description = "Generate htpasswd file for FileFlows Traefik basic auth";
    before = [ "traefik.service" ];
    requiredBy = [ "traefik.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.apacheHttpd}/bin/htpasswd -bc /run/traefik-fileflows-htpasswd admin "$(cat ${config.age.secrets.fileflows-password.path})"
      ${pkgs.coreutils}/bin/chmod 644 /run/traefik-fileflows-htpasswd
    '';
  };

  users.users = {
    radarr = {
      isSystemUser = true;
      group = "radarr";
      extraGroups = [ "media" ];
    };
    sonarr = {
      isSystemUser = true;
      group = "sonarr";
      extraGroups = [ "media" ];
    };
    lidarr = {
      isSystemUser = true;
      group = "lidarr";
      extraGroups = [ "media" ];
    };
    readarr = {
      isSystemUser = true;
      group = "readarr";
      extraGroups = [ "media" ];
    };
  };
}
