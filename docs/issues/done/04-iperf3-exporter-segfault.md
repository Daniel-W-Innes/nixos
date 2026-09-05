# iperf3-exporter segfaults — pin or replace the image

**DONE 2026-09-05.** Replaced, not pinned: the segfaulting process was the image's bundled Alpine musl iperf3 (`comm=iperf3`, crash in `ld-musl`), and every published tag ships the same `FROM alpine:3.21; apk add iperf3` — pinning was a coin-flip. Shipped as `generic/server/iperf-probe.nix` (option 2): an hourly systemd timer runs nixpkgs iperf3 (glibc) from melon against all three targets and writes the same `iperf3_*` metric names with `target`/`port` labels into the node_exporter textfile collector (`--collector.textfile.directory=/run/iperf-probe`), so the Grafana iperf3 dashboard (separate git-synced repo, queries keyed only on target/port) needs no changes. Probe job, oci-container, and process-exporter group removed; per-target failures emit `iperf3_up 0` only. Beyond exporter parity it also emits `iperf3_sent/received_bytes_per_second`, `iperf3_rtt_min/mean/max_seconds`, `iperf3_reorder`, and `iperf3_max_snd_cwnd/wnd_bytes` (TCP quality, no extra iperf3 flags needed — all in the `-J` output), plus a gated second pass with `-R` emitting `iperf3_reverse_retransmits` — the target's own send-side retransmit count, the one reverse-direction TCP stat the default run's JSON lacks. Deploy + first hourly run on melon still pending as of writing (see verification below).

### Problem

The hourly speed-test scrape (`job="iperf3"`, targets cucamelon/onion/pumpkin, exporter container at `localhost:9579`, `generic/server/visibility.nix:539-567,886-891`) is broken. Kernel log 2026-09-04T01:47:45Z during the transmission investigation:

```
iperf3[4093845]: segfault at 28 ip 00007b9af296af87 sp 00007ffe23e631e0 error 4 in ld-musl-x86_64.so.1
```

`ghcr.io/edgard/iperf3_exporter:latest` crashes mid-test (musl bug). Hourly speed metrics are not being collected, and the segfaults add noise to kernel-log queries during incidents.

### Fix (pick one)

1. **Pin** `ghcr.io/edgard/iperf3_exporter` to an older tag and test whether the probe completes (check Prometheus for `iperf3_*` probe metrics an hour after deploy).
2. **Replace** with a small systemd timer + script: run `iperf3 -J -c <target> -p 5201` against each host and write results into the node_exporter textfile collector (same pattern as Issue 3). Zero container, no image dependency.

### Verification

- After an hourly scrape: `up{job="iperf3"}` samples exist with probe metrics for all three targets; no new `iperf3.*segfault` kernel lines.

### References

- `docs/debug.md` §"Known noise"
