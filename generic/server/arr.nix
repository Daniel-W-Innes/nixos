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

  # Prebuilt WASM plugin. pname must match the manifest id so navidrome's
  # package links share/plugins/${pname}.ndp (pkgs/by-name/na/navidrome/package.nix).
  audiomuseaiPlugin = pkgs.stdenv.mkDerivation {
    pname = "audiomuseai";
    version = "10.0.0";

    src = pkgs.fetchurl {
      url = "https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin/releases/download/v10/audiomuseai.ndp";
      hash = "sha256-wTjprxbwl9jNB6yVf7iknZGn2gZuW0oUV8rb1HmqEKc=";
    };

    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      install -Dm644 $src $out/share/audiomuseai.ndp
    '';

    passthru = {
      isNavidromePlugin = true;
    };

    meta = {
      description = "AudioMuse-AI Instant Mix plugin for Navidrome";
      homepage = "https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin";
      license = lib.licenses.agpl3Only;
    };
  };
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
      {
        port = config.services.rtorrent.port;
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

  systemd.services = {
    rtorrent.vpnConfinement = {
      enable = true;
      vpnNamespace = "proton";
    };

    # Flood reaches rtorrent's SCGI unix socket (/run/rtorrent/rpc.sock, group
    # rtorrent, g+w) from the host namespace — the socket lives in /run, which
    # the proton network namespace does not isolate. It also mkdirs add-torrent
    # destinations on /mnt/media itself, so it needs the media group too.
    flood.serviceConfig.SupplementaryGroups = [
      "rtorrent"
      "media"
    ];

    # The XML-RPC proxy only fronts rtorrent's socket — start after it.
    nginx.after = [ "rtorrent.service" ];

    prometheus-wireguard-exporter = lib.mkIf config.services.prometheus.exporters.wireguard.enable {
      vpnConfinement = {
        enable = true;
        vpnNamespace = "proton";
      };
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
        download-dir = "/mnt/media/downloads";
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
    rtorrent = {
      enable = true;
      port = 51821;
      downloadDir = "/mnt/media/downloads";
      # The module template defaults to conservative private-tracker settings
      # (dht.mode disable, pex no, udp trackers no); this instance targets
      # public trackers like transmission.
      configText = ''
        # dht.mode is "on", not "auto": in rakshasa 0.16 "auto" only starts DHT
        # from DownloadList::resume() (session recovery at daemon boot) —
        # torrents added to a running daemon never trigger it, so a trackerless
        # magnet immediately fails with "No DHT nodes available for peer search"
        # (the errored arch ISO, 2026-11-12). "on" starts DHT at boot via
        # load_dht_cache() and has no auto mode's 15-minute idle auto-stop.
        dht.mode.set = on
        protocol.pex.set = yes
        trackers.use_udp.set = yes

        # DHT bootstrap routers. libtorrent has NO built-in defaults — without
        # these (or a warm session/rtorrent.dht_cache) bootstrap never starts.
        # Syntax is host:port (the comma form on old wiki pages silently
        # resolves the whole "host,port" string as a hostname and fails).
        dht.add_node = dht.transmissionbt.com:6881
        dht.add_node = dht.libtorrent.org:25401
        dht.add_node = dht.aelitis.com:6881

        # Mirror transmission's seeding policy: stop at 5.0 ratio (500%, max
        # 550% gives hysteresis; upload floor zeroed so small torrents stop
        # too — transmission's ratio_limit=5.0 has no floor). This uses the
        # built-in group.insert = seeding,seeding machinery shipped in
        # rtorrent's own rc: group.seeding.ratio.* values + the on_ratio
        # schedule (same name the enable method would create, so
        # group.seeding.ratio.disable still removes it). Close command is the
        # shipped default d.try_close + d.ignore_commands.set. Remove the
        # schedule2 line to seed indefinitely.
        group.seeding.ratio.min.set = 500
        group.seeding.ratio.max.set = 550
        group.seeding.ratio.upload.set = 0
        schedule2 = group.seeding.ratio, 5, 60, ((on_ratio, seeding))

        # Flood requires these aliases on rakshasa/rtorrent > 0.15.1: without
        # them load.* is missing from the command map it probes over JSON-RPC,
        # so every add-torrent call fails instantly (POST /api/torrents/add-urls 500).
        method.redirect = load.throw,load.normal
        method.redirect = load.start_throw,load.start
        method.insert = d.down.sequential,value|const,0
        method.insert = d.down.sequential.set,value|const,0
      '';
    };
    flood = {
      enable = true;
      # Explicit loopback, not the module's "localhost" default (which can
      # resolve to ::1 and leave traefik pointing at an unreachable backend).
      # Auth comes from traefik's flood-auth middleware, so flood's own auth
      # is off.
      host = "127.0.0.1";
      port = 3002;
      extraArgs = [
        "--rtsocket=/run/rtorrent/rpc.sock"
        "--auth=none"
      ];
    };
    # HTTP XML-RPC front for rtorrent's SCGI socket so the arr apps can use
    # rtorrent as a download client: their rTorrent client type speaks
    # XML-RPC over HTTP, while bare rtorrent serves SCGI only on
    # /run/rtorrent/rpc.sock. Loopback-only — the arrs connect from this
    # host. No SCGI auth (the local socket is open; flood and the exporter
    # already connect without credentials). Port 51821 is the BitTorrent
    # peer port, not an RPC endpoint.
    nginx = {
      enable = true;
      virtualHosts."rtorrent-rpc" = {
        listen = [
          {
            addr = "127.0.0.1";
            port = 5000;
          }
        ];
        locations."/RPC2" = {
          extraConfig = ''
            include scgi_params;
            scgi_pass unix:/run/rtorrent/rpc.sock;
          '';
        };
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
      plugins = [ audiomuseaiPlugin ];
      settings = {
        EnableInsightsCollector = true;
        MusicFolder = "/mnt/media/music";
        BaseUrl = "https://navidrome.lc.brotherwolf.ca";
        "Prometheus.Enabled" = true;
        # Plugin docs require audiomuseai first (replaces default
        # "deezer,lastfm,listenbrainz"); lastfm/deezer stay inert without keys.
        Agents = "audiomuseai,lastfm,deezer";
        # v10 plugin README recommends this so fresh analyses are visible.
        DevArtistInfoTimeToLive = "1s";
      };
    };
    jellyfin = {
      enable = true;
      group = "media";
    };
  };
  users.users = {
    rtorrent = {
      # CIFS mount is uid=media gid=media with 0660/0770 modes.
      extraGroups = [ "media" ];
    };
    nginx = {
      # The nginx workers (master drops privileges) connect to rtorrent's
      # SCGI socket for the XML-RPC proxy: /run/rtorrent and rpc.sock are
      # rtorrent:rtorrent.
      extraGroups = [ "rtorrent" ];
    };
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
