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
            read -r sb ss rb rs rt < <(printf '%s\n' "$json" | jq -r '[.end.sum_sent.bytes? // 0, .end.sum_sent.seconds? // 0, .end.sum_received.bytes? // 0, .end.sum_received.seconds? // 0, .end.sum_sent.retransmits? // 0] | @tsv')
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
  systemd.services.prometheus-node-exporter.serviceConfig.RuntimeDirectory =
    [ "prometheus-node-exporter iperf-probe" ];
  # Covers a manual start before the exporter has run this boot.
  systemd.services.iperf-probe = {
    description = "Hourly iperf3 speed tests feeding the node_exporter textfile collector";
    after = [ "prometheus-node-exporter.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /run/iperf-probe";
      ExecStart = "${probe}/bin/iperf-probe";
      TimeoutStartSec = 180;
    };
  };
  systemd.timers.iperf-probe = {
    description = "Hourly iperf3 speed tests";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      RandomizedDelaySec = 300;
      Persistent = true;
    };
  };
}
