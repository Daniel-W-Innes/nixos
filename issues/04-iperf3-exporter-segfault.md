# iperf3-exporter segfaults — pin or replace the image

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
