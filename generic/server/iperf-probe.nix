# Hourly LAN speed tests replacing the segfaulting ghcr.io/edgard/iperf3_exporter
# podman container (docs/issues/04). The image shipped an Alpine musl iperf3 that
# crashed mid-test; nixpkgs iperf3 (glibc) has no such problem. Results feed the
# node_exporter textfile collector, keeping the iperf3_* metric names and
# target/port labels the Grafana iperf3 dashboard queries.
{
  pkgs,
  ...
}:

let
  probe = pkgs.writeShellApplication {
    name = "iperf-probe";
    runtimeInputs = with pkgs; [
      coreutils
      iperf3
      jq
    ];
    text = ''
      set -euo pipefail

      # One .prom per target so a failed probe only gaps that target. The
      # textfile collector only reads *.prom files, so the .tmp suffix keeps a
      # partially-written file invisible; mv makes the swap atomic.
      dir=/run/iperf-probe
      for target in cucamelon.lc.brotherwolf.ca onion.lc.brotherwolf.ca pumpkin.lc.brotherwolf.ca; do
        out="$dir/iperf3-$target.prom"
        tmp="$out.tmp"
        {
          echo '# HELP iperf3_up Whether the most recent hourly iperf3 test to the target succeeded (1) or failed (0).'
          echo '# TYPE iperf3_up gauge'
          # -t 5 matches the old exporter's 5s default; timeout guards a wedged
          # server. stderr is kept so a failure's reason lands in the journal;
          # the .end gate still requires valid JSON before emitting up=1.
          if json=$(timeout 35 iperf3 -J -t 5 -c "$target" -p 5201 2>&1) \
            && printf '%s\n' "$json" | jq -e '.end' >/dev/null 2>&1; then
            read -r sb ss rb rs rt sbs rbs rttmin rttmean rttmax reorder cwnd wnd < <(
              printf '%s\n' "$json" | jq -r '
                [.end.sum_sent.bytes? // 0,
                 .end.sum_sent.seconds? // 0,
                 .end.sum_received.bytes? // 0,
                 .end.sum_received.seconds? // 0,
                 .end.sum_sent.retransmits? // 0,
                 (.end.sum_sent.bits_per_second? // 0) / 8,
                 (.end.sum_received.bits_per_second? // 0) / 8,
                 ((.end.streams[0].sender.min_rtt)? // 0) / 1e6,
                 ((.end.streams[0].sender.mean_rtt)? // 0) / 1e6,
                 ((.end.streams[0].sender.max_rtt)? // 0) / 1e6,
                 .end.streams[0].sender.reorder? // 0,
                 .end.streams[0].sender.max_snd_cwnd? // 0,
                 .end.streams[0].sender.max_snd_wnd? // 0] | @tsv')
            echo "iperf3_up{target=\"$target\",port=\"5201\"} 1"
            echo '# HELP iperf3_sent_bytes Bytes sent during the most recent hourly test.'
            echo '# TYPE iperf3_sent_bytes gauge'
            echo "iperf3_sent_bytes{target=\"$target\",port=\"5201\"} $sb"
            echo '# HELP iperf3_sent_seconds Seconds the most recent hourly test spent sending.'
            echo '# TYPE iperf3_sent_seconds gauge'
            echo "iperf3_sent_seconds{target=\"$target\",port=\"5201\"} $ss"
            echo '# HELP iperf3_received_bytes Bytes received during the most recent hourly test.'
            echo '# TYPE iperf3_received_bytes gauge'
            echo "iperf3_received_bytes{target=\"$target\",port=\"5201\"} $rb"
            echo '# HELP iperf3_received_seconds Seconds the most recent hourly test spent receiving.'
            echo '# TYPE iperf3_received_seconds gauge'
            echo "iperf3_received_seconds{target=\"$target\",port=\"5201\"} $rs"
            echo '# HELP iperf3_retransmits TCP retransmits during the most recent hourly test.'
            echo '# TYPE iperf3_retransmits gauge'
            echo "iperf3_retransmits{target=\"$target\",port=\"5201\"} $rt"
            echo '# HELP iperf3_sent_bytes_per_second Average throughput in bytes per second in the sending direction during the most recent hourly test.'
            echo '# TYPE iperf3_sent_bytes_per_second gauge'
            echo "iperf3_sent_bytes_per_second{target=\"$target\",port=\"5201\"} $sbs"
            echo '# HELP iperf3_received_bytes_per_second Average throughput in bytes per second in the receiving direction during the most recent hourly test.'
            echo '# TYPE iperf3_received_bytes_per_second gauge'
            echo "iperf3_received_bytes_per_second{target=\"$target\",port=\"5201\"} $rbs"
            echo '# HELP iperf3_rtt_min_seconds Minimum round-trip time measured during the most recent hourly test.'
            echo '# TYPE iperf3_rtt_min_seconds gauge'
            echo "iperf3_rtt_min_seconds{target=\"$target\",port=\"5201\"} $rttmin"
            echo '# HELP iperf3_rtt_mean_seconds Mean round-trip time measured during the most recent hourly test.'
            echo '# TYPE iperf3_rtt_mean_seconds gauge'
            echo "iperf3_rtt_mean_seconds{target=\"$target\",port=\"5201\"} $rttmean"
            echo '# HELP iperf3_rtt_max_seconds Maximum round-trip time measured during the most recent hourly test.'
            echo '# TYPE iperf3_rtt_max_seconds gauge'
            echo "iperf3_rtt_max_seconds{target=\"$target\",port=\"5201\"} $rttmax"
            echo '# HELP iperf3_reorder Packets detected out of order during the most recent hourly test.'
            echo '# TYPE iperf3_reorder gauge'
            echo "iperf3_reorder{target=\"$target\",port=\"5201\"} $reorder"
            echo '# HELP iperf3_max_snd_cwnd_bytes Maximum sending congestion window during the most recent hourly test.'
            echo '# TYPE iperf3_max_snd_cwnd_bytes gauge'
            echo "iperf3_max_snd_cwnd_bytes{target=\"$target\",port=\"5201\"} $cwnd"
            echo '# HELP iperf3_max_snd_wnd_bytes Maximum sending window during the most recent hourly test.'
            echo '# TYPE iperf3_max_snd_wnd_bytes gauge'
            echo "iperf3_max_snd_wnd_bytes{target=\"$target\",port=\"5201\"} $wnd"
            # Reverse pass: the default run's JSON only carries the client's
            # own sender stats; the target's send direction (target -> melon)
            # is invisible except for bytes. A -R run returns the target's
            # retransmit count in sum_sent - the one TCP-quality signal iperf3
            # servers report (their RTT/cwnd come back as 0). Skipped when the
            # forward pass failed: the target is already up=0, no point
            # spending another timeout on it.
            if rjson=$(timeout 35 iperf3 -J -R -t 5 -c "$target" -p 5201 2>&1) \
              && printf '%s\n' "$rjson" | jq -e '.end' >/dev/null 2>&1; then
              rretr=$(printf '%s\n' "$rjson" | jq -r '.end.sum_sent.retransmits? // 0')
              echo '# HELP iperf3_reverse_retransmits TCP retransmits reported by the target while sending to melon during the most recent hourly test.'
              echo '# TYPE iperf3_reverse_retransmits gauge'
              echo "iperf3_reverse_retransmits{target=\"$target\",port=\"5201\"} $rretr"
            else
              echo "iperf3 reverse probe to $target failed" >&2
              printf '%s\n' "$rjson" | tail -n 1 >&2
            fi
          else
            echo "iperf3_up{target=\"$target\",port=\"5201\"} 0"
            echo "iperf3 probe to $target failed" >&2
            printf '%s\n' "$json" | tail -n 1 >&2
          fi
        } > "$tmp"
        mv -f "$tmp" "$out"
      done
    '';
  };
in
{
  # textfile collector over /run/iperf-probe (default-enabled in node_exporter,
  # but listed explicitly for clarity). The exporter only reads the dir, so
  # ownership doesn't matter much; keeping it on the exporter's
  # RuntimeDirectory list makes systemd create it at every node_exporter start
  # (boot and restarts), with no window where the textfile collector scrapes a
  # missing directory.
  services.prometheus.exporters.node = {
    enabledCollectors = [ "textfile" ];
    extraFlags = [ "--collector.textfile.directory=/run/iperf-probe" ];
  };
  systemd = {
    services.prometheus-node-exporter.serviceConfig.RuntimeDirectory = [
      "prometheus-node-exporter iperf-probe"
    ];
    # Covers a manual start before the exporter has run this boot.
    services.iperf-probe = {
      description = "Hourly iperf3 speed tests feeding the node_exporter textfile collector";
      after = [ "prometheus-node-exporter.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /run/iperf-probe";
        ExecStart = "${probe}/bin/iperf-probe";
        TimeoutStartSec = 180;
      };
    };
    timers.iperf-probe = {
      description = "Hourly iperf3 speed tests";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        RandomizedDelaySec = 300;
        Persistent = true;
      };
    };
  };
}
