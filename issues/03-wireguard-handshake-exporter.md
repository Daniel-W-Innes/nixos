# Export Proton wg handshake age from the VPN namespace + Grafana alert

### Problem

Transmission runs confined in the `proton` network namespace (`vpnNamespaces`/`vpnConfinement` in `generic/server/arr.nix`). The namespace is invisible to host exporters: the only signal is the `proton-br` bridge keepalive counter. The 2026-09-03 transmission outage (RPC dead 21:35–21:56 EDT) was caused by the Proton tunnel dropping — and it was only diagnosable by triangulating bridge counters, NIC rates, and LAN-scrape continuity. `wg show latest-handshakes` (requires `ip netns exec proton`) would have shown the drop instantly. It currently needs sudo, which is why the investigation couldn't run it.

### Fix

1. Add a textfile-collector script + systemd timer on melon: runs `ip netns exec proton wg show latest-handshakes` (and optionally `wg show endpoints`) and writes a prom textfile, e.g. `/var/lib/node_exporter/textfile_collector/wg_proton.prom` with a metric like:

   ```
   wireguard_latest_handshake_seconds{namespace="proton",interface="wg0"} <age>
   ```

2. Enable node_exporter's textfile collector for that directory: `services.prometheus.exporters.node.textfile.directory` in `generic/prometheus.nix`.
3. Give the timer/script the needed privilege (root timer unit, or a sudoers entry for the script).
4. Add a Grafana alert rule: handshake age > 300 s (or `changes()` stall) → notify Gotify, so a tunnel drop pages before it takes out transmission.
5. Optional but cheap: a "melon symptoms" Grafana dashboard — ens3 TX/RX rate, proton-br keepalive rate, node_load1, MemAvailable, kuma Transmission status — so future incidents are one screen instead of ~10 queries.

### Verification

- `wireguard_latest_handshake_seconds` present in Prometheus, updating each timer tick.
- Kill the tunnel (or wait for a Proton rotation) → alert fires.
- The metric confirms the 2026-09-03 diagnosis if Proton's logs/rotation window is still checkable.

### References

- `docs/debug.md` §"Topology cheat sheet" and §"Planned fixes"
