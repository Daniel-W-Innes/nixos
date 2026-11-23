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

  piaNs = config.services.vpnConfinement.namespaces.pia;
  # The host reaches services in the pia namespace over the hostLink veth
  # pair (a /30 carved from 169.254.0.0/16, derived from the namespace name).
  piaNsAddr = piaNs.derived.hostLink.nsAddressIPv4;
  piaHostAddr = piaNs.derived.hostLink.hostAddressIPv4;

  # Fetches the PIA forwarded port and keeps the mapping alive. Runs inside
  # the pia namespace (the PF API lives on the tunnel gateway). Flow follows
  # PIA's official manual-connections scripts:
  #   token (24h) -> getSignature -> bindPort keepalive every 15 min.
  piaPortForward = pkgs.writeShellApplication {
    name = "pia-port-forward";
    runtimeInputs = with pkgs; [
      curl
      jq
      coreutils
      gnused
      gawk
      iproute2
    ];
    text = ''
      set -euo pipefail

      # $CREDENTIALS_DIRECTORY (systemd LoadCredential) holds the agenix
      # secrets with the dynamic user's ownership.
      state_dir=/run/pia-port-forward

      user=$(sed -n '1p' "$CREDENTIALS_DIRECTORY/pia-creds")
      pass=$(sed -n '2p' "$CREDENTIALS_DIRECTORY/pia-creds")

      # Gateway of the tunnel inside this namespace (redirect-gateway def1
      # installs 0.0.0.0/1 and 128.0.0.0/1 via the gateway). Scoped to pia0:
      # the endpoint-exemption /32 route via the hostLink sorts first in an
      # unscoped listing and would be picked as the "gateway" (2026-11-22).
      gw=$(ip route show dev pia0 | awk '/ via / { print $3; exit }')
      [ -n "$gw" ] || gw=10.0.0.1

      # Server hostname (TLS SNI) from the .ovpn, plus a combined trust
      # bundle. This fleet serves the PF API (gateway:19999) with Let's
      # Encrypt certs — verified only by the system store (2026-11-22:
      # ca-montreal gateway chain, curl 60 against the .ovpn CA alone) —
      # while older servers still use certs from the .ovpn's own CA.
      # Concatenating both covers either generation.
      host=$(awk '$1 == "remote" { print $2; exit }' "$CREDENTIALS_DIRECTORY/pia-vpn")
      ca="$state_dir/ca-combined.crt"
      {
        cat /etc/ssl/certs/ca-certificates.crt
        awk '/<ca>/{ f = 1; next } /<\/ca>/{ f = 0 } f' "$CREDENTIALS_DIRECTORY/pia-vpn"
      } > "$ca"

      # Reuse the signature while the token is fresh (24h) so the port stays
      # pinned; regenerate both afterwards.
      state="$state_dir/state"
      if [ -f "$state" ] && [ "$(( $(date +%s) - $(jq -r '.created' "$state") ))" -lt 86400 ]; then
        token=$(jq -r '.token' "$state")
        payload=$(jq -r '.payload' "$state")
        signature=$(jq -r '.signature' "$state")
      else
        token=$(curl -sS --fail --location --request POST \
          'https://www.privateinternetaccess.com/api/client/v2/token' \
          --form "username=$user" --form "password=$pass" | jq -r '.token')
        payload_and_signature=$(curl -sS --fail -G \
          --connect-to "$host::$gw:" --cacert "$ca" \
          --data-urlencode "token=$token" \
          "https://$host:19999/getSignature")
        [ "$(echo "$payload_and_signature" | jq -r '.status')" = "OK" ] ||
          { echo "getSignature failed: $payload_and_signature" >&2; exit 1; }
        payload=$(echo "$payload_and_signature" | jq -r '.payload')
        signature=$(echo "$payload_and_signature" | jq -r '.signature')
        jq -n --arg t "$token" --arg p "$payload" --arg s "$signature" \
          '{ token: $t, payload: $p, signature: $s, created: '"$(date +%s)"' }' > "$state"
      fi

      # The server drops the mapping without a bindPort every 15 minutes.
      curl -sS --fail -G \
        --connect-to "$host::$gw:" --cacert "$ca" \
        --data-urlencode "payload=$payload" \
        --data-urlencode "signature=$signature" \
        "https://$host:19999/bindPort" >/dev/null

      port=$(echo "$payload" | base64 -d | jq -r '.port')
      echo "$port" > "$state_dir/port"
    '';
  };

  # Applies the fetched port on the host: opens it on the tunnel interface in
  # the namespace firewall and pushes it into transmission (live via RPC,
  # persisted into settings.json for restarts).
  piaPortForwardApply = pkgs.writeShellApplication {
    name = "pia-port-forward-apply";
    runtimeInputs = with pkgs; [
      coreutils
      iproute2
      nftables
      jq
      transmission_4
    ];
    text = ''
      set -euo pipefail

      state_dir=/run/pia-port-forward
      port_file="$state_dir/port"
      current_file="$state_dir/current"
      [ -f "$port_file" ] || exit 0
      port=$(cat "$port_file")
      current=$(cat "$current_file" 2>/dev/null || true)
      [ "$port" = "$current" ] && exit 0

      # Live update via RPC first — idempotent, and it fails clean when the
      # daemon is still loading its session, leaving no half-applied
      # firewall state behind (2026-11-22). The host reaches the namespace
      # over the veth. The credentialsFile is JSON merged into settings
      # (nixpkgs module), so pull rpc-username/rpc-password out of it.
      creds_file=${config.age.secrets.transmission.path}
      rpc_user=$(jq -r '."rpc-username" // empty' "$creds_file")
      rpc_pass=$(jq -r '."rpc-password" // empty' "$creds_file")
      transmission-remote ${piaNsAddr}:${toString config.services.transmission.settings.rpc-port} \
        -n "$rpc_user:$rpc_pass" --port "$port"

      # Swap the inbound ACCEPT rules on the tunnel interface in the netns.
      if [ -n "$current" ]; then
        ip netns exec pia nft delete rule inet vpnc input iifname "pia0" tcp dport "$current" accept 2>/dev/null || true
        ip netns exec pia nft delete rule inet vpnc input iifname "pia0" udp dport "$current" accept 2>/dev/null || true
      fi
      ip netns exec pia nft add rule inet vpnc input iifname "pia0" tcp dport "$port" accept
      ip netns exec pia nft add rule inet vpnc input iifname "pia0" udp dport "$port" accept

      # Persist for restarts (the daemon loads settings.json on start).
      settings=/var/lib/transmission/.config/transmission-daemon/settings.json
      jq --argjson p "$port" '."peer-port" = $p' "$settings" > "$settings.tmp" \
        && chown transmission:media "$settings.tmp" \
        && chmod 600 "$settings.tmp" \
        && mv "$settings.tmp" "$settings"

      echo "$port" > "$current_file"
    '';
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

    pia-vpn = lib.mkIf config.services.transmission.enable {
      file = secretsDir + /pia-vpn.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    pia-credentials = lib.mkIf config.services.transmission.enable {
      file = secretsDir + /pia-credentials.age;
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

  services.vpnConfinement = {
    enable = true;
    namespaces.pia = {
      enable = true;
      openvpn = {
        enable = true;
        interface = "pia0";
        configFile = config.age.secrets.pia-vpn.path;
        credentialsFile = config.age.secrets.pia-credentials.path;
      };
      dns.servers = [
        "10.0.0.243"
        "10.0.0.244"
      ];
      # The RPC is reachable from the host at the veth address (traefik's
      # target is rpc-bind-address below, and port-forward-apply pushes the
      # peer-port over it).
      publishToHost.tcp = [ 9091 ];
    };
  };

  systemd.services.transmission = {
    vpn = {
      enable = true;
      namespace = "pia";
      # baseline, not strict: strict makes the whole tree read-only, which
      # would break downloads on the /mnt/media CIFS mount.
      hardeningProfile = "baseline";
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

  systemd.services.pia-port-forward = {
    description = "PIA port-forward keepalive (runs inside the pia namespace)";
    wantedBy = [ "vpn-confinement-openvpn@pia.service" ];
    # Pull the apply unit into every keepalive transaction. (Service-level
    # wantedBy on the apply unit is inert on NixOS — it only emits an
    # [Install] section, and nothing ever runs systemctl enable.)
    wants = [ "pia-port-forward-apply.service" ];
    vpn = {
      enable = true;
      namespace = "pia";
      # iproute2 inspects the ns route table; the wrapper's
      # RestrictAddressFamilies default is AF_UNIX+AF_INET only when ipv6
      # is disabled, which kills AF_NETLINK with EAFNOSUPPORT ("Cannot open
      # netlink socket: Address family not supported by protocol",
      # 2026-11-22).
      extraAddressFamilies = [ "AF_NETLINK" ];
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${piaPortForward}/bin/pia-port-forward";
      DynamicUser = true;
      LoadCredential = [
        "pia-creds:${config.age.secrets.pia-credentials.path}"
        "pia-vpn:${config.age.secrets.pia-vpn.path}"
      ];
      RuntimeDirectory = "pia-port-forward";
      RuntimeDirectoryMode = "0755";
    };
  };

  systemd.services.pia-port-forward-apply = {
    description = "Apply the PIA forwarded port to transmission and the namespace firewall";
    # Triggered by pia-port-forward's wants (see there).
    after = [
      "pia-port-forward.service"
      "vpn-confinement-openvpn@pia.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${piaPortForwardApply}/bin/pia-port-forward-apply";
    };
  };

  systemd.timers.pia-port-forward = {
    description = "PIA port-forward keepalive timer (every 15 minutes)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/15";
      Persistent = true;
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
        rpc-bind-address = piaNsAddr;
        rpc-whitelist = piaHostAddr;
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
