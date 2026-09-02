{
  config,
  pkgs,
  ...
}:

let
  # Slow-rotation search of the wanted/missing list (12K+ albums). Bulk
  # MissingAlbumSearch hammered the indexers and wedged the queue state
  # machine (2026-09-02 incident), so this drips AlbumSearch in small
  # batches instead. Rotation is fair without a state file: each run sorts
  # by lastSearchTime (never-searched first) and skips anything searched
  # within MIN_GAP_HOURS, so every album gets one search per sweep cycle.
  dripScript = pkgs.writeShellApplication {
    name = "lidarr-search-drip";
    runtimeInputs = with pkgs; [
      curl
      jq
    ];
    text = ''
      KEY="$(cat "$CREDENTIALS_DIRECTORY/lidarr-api-key")"
      URL="http://127.0.0.1:8686"
      BATCH="''${BATCH:-25}"
      MIN_GAP_HOURS="''${MIN_GAP_HOURS:-72}"

      # Fetch every page of the missing list (~13 requests for 12K albums).
      pages=$(mktemp -d)
      trap 'rm -rf "$pages"' EXIT
      page=1
      while :; do
        curl -fsS --retry 2 --retry-delay 5 --retry-connrefused \
          -H "X-Api-Key: $KEY" \
          "$URL/api/v1/wanted/missing?page=''${page}&pageSize=1000" \
          -o "$pages/''${page}.json"
        count=$(jq '.records | length' "$pages/''${page}.json")
        if [ "$count" -lt 1000 ]; then
          break
        fi
        page=$((page + 1))
      done

      # Skip unreleased albums (RSS catches those at release) and anything
      # searched within MIN_GAP_HOURS, then take the oldest-searched first.
      cutoff=$(( $(date +%s) - MIN_GAP_HOURS * 3600 ))
      ids=$(jq -s --argjson cutoff "$cutoff" --argjson batch "$BATCH" '
        [ .[].records[] ]
        | map(select(
              (try (.releaseDate | fromdateiso8601) catch null)
              | . == null or . <= now))
        | map(select(
              (try (.lastSearchTime | fromdateiso8601) catch null)
              | . == null or . <= $cutoff))
        | sort_by(.lastSearchTime // "0000-01-01T00:00:00Z")
        | .[0:$batch] | map(.id)
      ' "$pages"/*.json)

      n=$(echo "$ids" | jq length)
      if [ "$n" -gt 0 ]; then
        curl -fsS --retry 2 --retry-delay 5 --retry-connrefused \
          -X POST -H "X-Api-Key: $KEY" -H "Content-Type: application/json" \
          -d "{\"name\":\"AlbumSearch\",\"albumIds\":$ids}" \
          "$URL/api/v1/command"
        echo "queued AlbumSearch for $n albums"
      else
        echo "nothing to search this run"
      fi
    '';
  };
in
{
  systemd.services.lidarr-search-drip = {
    description = "lidarr-search-drip: rotate AlbumSearch over missing albums in small batches";
    requires = [ "lidarr.service" ];
    after = [
      "network.target"
      "lidarr.service"
    ];
    environment = {
      BATCH = "25";
      MIN_GAP_HOURS = "72";
    };
    serviceConfig = {
      ExecStart = "${dripScript}/bin/lidarr-search-drip";
      LoadCredential = "lidarr-api-key:${config.age.secrets.lidarr-api-key.path}";
      User = "lidarr";
      Group = "lidarr";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };

  systemd.timers.lidarr-search-drip = {
    description = "lidarr-search-drip: every 4h, search up to 25 least-recently-searched missing albums";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00,04,08,12,16,20:17";
      RandomizedDelaySec = 300;
      Persistent = true;
    };
  };
}
