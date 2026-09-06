{
  pkgs,
  ...
}:

let
  writeSuccessMetric = pkgs.writeShellApplication {
    name = "borgmatic-write-success-metric";
    runtimeInputs = [
      pkgs.borgbackup
      pkgs.borgmatic
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      set -euo pipefail
      dir=/var/lib/borgmatic
      tmp="$dir/borgmatic.prom.tmp"
      out="$dir/borgmatic.prom"
      {
        echo '# HELP borgmatic_last_success Unix time of the most recent successful borgmatic backup.'
        echo '# TYPE borgmatic_last_success gauge'
        echo "borgmatic_last_success $(date +%s)"
      } > "$tmp"
      info=$(borgmatic info --json --verbosity -2 2>/dev/null) || true
      if [ -n "$info" ]; then
        start=$(printf '%s' "$info" | jq -r '.archives[0].start // empty' 2>/dev/null || true)
        end=$(printf '%s' "$info" | jq -r '.archives[0].end // empty' 2>/dev/null || true)
        if [ -n "$start" ] && [ -n "$end" ]; then
          duration=$(( $(date -d "$end" +%s) - $(date -d "$start" +%s) ))
          {
            echo '# HELP borgmatic_last_backup_duration_seconds Duration of the most recent successful backup, from archive start to end.'
            echo '# TYPE borgmatic_last_backup_duration_seconds gauge'
            echo "borgmatic_last_backup_duration_seconds $duration"
          } >> "$tmp"
        fi
        ucs=$(printf '%s' "$info" | jq -r '(.cache.stats.unique_csize // .archives[0].stats.unique_csize // empty)' 2>/dev/null || true)
        tcs=$(printf '%s' "$info" | jq -r '(.cache.stats.total_csize // .archives[0].stats.total_csize // empty)' 2>/dev/null || true)
        if [ -n "$ucs" ]; then
          {
            echo '# HELP borgmatic_repository_deduplicated_size_bytes Compressed size of unique chunks in the repository.'
            echo '# TYPE borgmatic_repository_deduplicated_size_bytes gauge'
            echo "borgmatic_repository_deduplicated_size_bytes $ucs"
          } >> "$tmp"
        fi
        if [ -n "$tcs" ]; then
          {
            echo '# HELP borgmatic_repository_total_size_bytes Compressed size of all chunks in the repository, before deduplication.'
            echo '# TYPE borgmatic_repository_total_size_bytes gauge'
            echo "borgmatic_repository_total_size_bytes $tcs"
          } >> "$tmp"
        fi
      fi
      mv -f "$tmp" "$out"
    '';
  };
in
{
  services.borgmatic = {
    enable = true;
    settings = {
      source_directories = [
        "/home"
        "/etc"
        "/root"
        "/var"
      ];

      repositories = [
        {
          path = "/run/media/daniel/stb/repo";
          label = "local";
        }
      ];

      exclude_patterns = [
        "/home/*/.cache"
        "*/steamapps"
      ];
      exclude_caches = true;

      compression = "zstd,7";
      recompress = "if-different";
      retries = 3;

      archive_name_format = "borgmatic_{hostname}_{now:%Y-%m-%dT%H:%M:%S.%f}";

      keep_daily = 7;
      keep_weekly = 4;
      keep_yearly = 1;

      checks = [
        {
          name = "archives";
          frequency = "1 days";
        }
        {
          name = "repository";
          frequency = "2 weeks";
        }
        {
          name = "spot";
          count_tolerance_percentage = 0.1;
          data_sample_percentage = 5;
          data_tolerance_percentage = 1;
          frequency = "1 month";
        }
      ];

      after_actions = [ "${writeSuccessMetric}/bin/borgmatic-write-success-metric" ];
    };
  };

  services.prometheus.exporters.node = {
    enabledCollectors = [ "textfile" ];
    extraFlags = [ "--collector.textfile.directory=/var/lib/borgmatic" ];
  };
}
