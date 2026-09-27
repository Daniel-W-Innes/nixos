# Worked example (abridged)


2026-09-03, "transmission on melon stopped working ~50 min ago":

1. `list_loki_label_names` → labels are hostname/job/level/service_name; no unit.
2. Timeline: `{service_name="systemd-journal"} |= "MONITOR"` over ±2 h of the complaint → kuma Down at 21:45:34 EDT, Up at 21:56:55 EDT.
3. Scope: `|= "\"_SYSTEMD_UNIT\":\"lidarr.service\""` etc. → all arrs failing with `DownloadClientUnavailableException` only during that window.
4. Kill hypotheses with one query each: `min_over_time(up{instance=~"onion.*"}[3h])` (LAN fine); `node_load1`/`node_memory_MemAvailable_bytes` (no OOM/CPU cause); kernel lines with a CIFS filter (no mount errors); journal regex for `(vpn|wg-quick|proton)` (no namespace reconfiguration).
5. `rate(node_network_transmit_bytes_total{instance="localhost:9100",device=~"ens3|proton-br"}[5m])` → ens3 collapse during the outage; `proton-br` keepalive degradation bracketing it → VPN tunnel drop froze transmission's single-threaded session (RPC shares the thread).
6. Rule-out misses: metar `gaierror` looked causal but `count_over_time` showed it's constant noise (`docs/debug/known-noise.md`).
