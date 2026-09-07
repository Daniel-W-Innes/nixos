{
  config,
  pkgs,
  secretsDir,
  ...
}:

let
  writeSuccessMetric = pkgs.writeShellApplication {
    name = "borgmatic-write-success-metric";
    runtimeInputs = [
      pkgs.borgbackup
      pkgs.coreutils
      pkgs.jq
      pkgs.util-linux
    ];
    text = ''
      set -euo pipefail
      dir=/var/lib/borgmatic
      tmp="$dir/borgmatic.prom.tmp"
      out="$dir/borgmatic.prom"
      exec 9>"$dir/.stats.lock"
      if ! flock -n 9; then
        exit 0
      fi
      info=""
      info=$(borg info --json --glob-archives 'borgmatic_{hostname}_*' /run/media/daniel/stb/repo 2>/dev/null) || true
      start=""
      end=""
      ucs=""
      tcs=""
      if [ -n "$info" ]; then
        start=$(printf '%s' "$info" | jq -r '[.archives[]] | sort_by(.end) | last | .start // empty' 2>/dev/null || true)
        end=$(printf '%s' "$info" | jq -r '[.archives[]] | sort_by(.end) | last | .end // empty' 2>/dev/null || true)
        ucs=$(printf '%s' "$info" | jq -r '.cache.stats.unique_csize // empty' 2>/dev/null || true)
        tcs=$(printf '%s' "$info" | jq -r '.cache.stats.total_csize // empty' 2>/dev/null || true)
      fi
      {
        echo '# HELP borgmatic_last_success Unix time the most recent archive in the repository finished, 0 if the repository holds no archives.'
        echo '# TYPE borgmatic_last_success gauge'
        if [ -n "$end" ]; then
          echo "borgmatic_last_success $(date -d "$end" +%s)"
        else
          echo 'borgmatic_last_success 0'
        fi
      } > "$tmp"
      if [ -n "$start" ] && [ -n "$end" ]; then
        duration=$(( $(date -d "$end" +%s) - $(date -d "$start" +%s) ))
        {
          echo '# HELP borgmatic_last_backup_duration_seconds Duration of the most recent archive, from start to end.'
          echo '# TYPE borgmatic_last_backup_duration_seconds gauge'
          echo "borgmatic_last_backup_duration_seconds $duration"
        } >> "$tmp"
      fi
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
        "/home/*/.local/share/Steam/steamrt64"
        "/home/*/.local/share/Steam/steamrt32"
        "/home/*/.local/share/Steam/ubuntu12_32"
        "/var/lib/containers/storage"
        "/home/*/.local/share/containers/storage"
        "/home/*/.local/share/Trash"
        "/home/*/.config/Code/Cache"
        "/home/*/.config/Code/CachedData"
        "/home/*/.config/Code/CachedExtensionVSIXs"
        "/home/*/.config/Code/WebStorage"
        "/home/*/.config/Code/GPUCache"
        "/home/*/.config/discord/Cache"
        "/home/*/go/pkg"
      ];
      exclude_caches = true;

      compression = "zstd,7";
      recompress = "if-different";
      retries = 3;

      archive_name_format = "borgmatic_{hostname}_{now:%Y-%m-%dT%H:%M:%S.%f}";

      keep_daily = 14;
      keep_weekly = 10;
      keep_yearly = 3;

      checks = [
        {
          name = "archives";
          frequency = "1 days";
        }
        {
          name = "repository";
          frequency = "1 month";
          only_run_on = [ "Saturday" ];
        }
        {
          name = "spot";
          count_tolerance_percentage = 0.1;
          data_sample_percentage = 5;
          data_tolerance_percentage = 1;
          xxh64sum_command = "${pkgs.xxhash}/bin/xxhsum";
          frequency = "2 month";
          only_run_on = [ "Sunday" ];
        }
        {
          name = "extract";
          frequency = "1 year";
          only_run_on = [ "Sunday" ];
        }
        {
          name = "data";
          frequency = "1 year";
          only_run_on = [ "Saturday" ];
        }
      ];

      commands = [
        {
          after = "repository";
          run = [ "${writeSuccessMetric}/bin/borgmatic-write-success-metric" ];
        }
      ];

      uptime_kuma = {
        push_url = "https://uptime.lc.brotherwolf.ca/api/push/\${KUMA_PUSH_TOKEN}";
      };
    };
  };

  age.secrets.borgmatic-env = {
    file = secretsDir + /borgmatic-env.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  systemd.services.borgmatic.serviceConfig = {
    ReadWritePaths = [ "/run/media/daniel/stb" ];
    EnvironmentFile = [ config.age.secrets.borgmatic-env.path ];
  };

  services.prometheus.exporters.node = {
    enabledCollectors = [ "textfile" ];
    extraFlags = [ "--collector.textfile.directory=/var/lib/borgmatic" ];
  };
}
