# Export Proton wg handshake age from the VPN namespace + Grafana alert

**DONE 2026-09-05.** Implemented with the [MindFlavor prometheus_wireguard_exporter](https://github.com/MindFlavor/prometheus_wireguard_exporter) (v3.6.6 from nixpkgs) instead of the textfile-collector plan below — it exposes the same signal plus per-peer endpoint/bytes without root timers or sudoers entries. Verified live on melon: exporter confined in the `proton` netns, scrape target healthy (up=1, 10 s interval), `wireguard_latest_handshake_delay_seconds` updating for all 4 proton0 peers; alert rules `wireguard-exporter-down` and `wireguard-handshake-stall` provisioned in the Grafana `visibility` folder → gotify-direct. The stall rule keys on `min()` over peers rather than any single peer: Proton keeps the three failover peers (`allowed_ips="(none)"`) handshaking every ~20–120 s while the active `0.0.0.0/0` peer routinely sits 20+ min stale when idle, so a per-peer threshold fires spuriously (observed live).

### Problem

Transmission runs confined in the `proton` network namespace (`vpnNamespaces`/`vpnConfinement` in `generic/server/arr.nix`). The namespace is invisible to host exporters: the only signal is the `proton-br` bridge keepalive counter. The 2026-09-03 transmission outage (RPC dead 21:35–21:56 EDT) was caused by the Proton tunnel dropping — and it was only diagnosable by triangulating bridge counters, NIC rates, and LAN-scrape continuity. `wg show latest-handshakes` (requires `ip netns exec proton`) would have shown the drop instantly. It currently needs sudo, which is why the investigation couldn't run it.

### Fix — as shipped

1. Exporter: `services.prometheus.exporters.wireguard` in `generic/server/visibility.nix` — `interfaces = ["proton0"]`, `withRemoteIp` (remote_ip/remote_port labels), `latestHandshakeDelay` (`wireguard_latest_handshake_delay_seconds`), listening on `192.168.15.1`.
2. Netns confinement: `prometheus-wireguard-exporter.service` gets `vpnConfinement` (in `generic/server/arr.nix`, gated on the exporter being enabled) because `proton0` exists only inside the `proton` namespace, plus `portMappings` 9586 to open the ns firewall (INPUT defaults to DROP).
3. Scrape target `192.168.15.1:9586` (the ns veth address) — **not** `localhost:9586`: the host's DNAT lives in `nat PREROUTING`, which never sees locally generated traffic (that path uses `nat OUTPUT`), so loopback can't reach the ns. Same reason the traefik→transmission RPC scrape uses `192.168.15.1:9091`.
4. Grafana alert rules (provisioned from `visibility.nix`, folder `visibility`, gotify-direct contact point, severity critical):
   - `wireguard-exporter-down` — `up{job="wireguard"} == 0`, for 3m. The exporter is bound to the proton ns service, so its death usually means the namespace or `proton0` vanished.
   - `wireguard-handshake-stall` — `min(wireguard_latest_handshake_delay_seconds{job="wireguard"}) > 300`, for 3m. Fires ~8 min after every peer's last handshake (i.e. the tunnel is really down, not just the active peer going quiet).
5. Optional but cheap: a "melon symptoms" Grafana dashboard — ens3 TX/RX rate, proton-br keepalive rate, node_load1, MemAvailable, kuma Transmission status — so future incidents are one screen instead of ~10 queries. Not done.

### Verification

- Exporter target healthy in Prometheus (single target `192.168.15.1:9586`, up=1); `wireguard_latest_handshake_delay_seconds`/`_seconds` present for all 4 peers with `interface="proton0"`, `public_key`, `remote_ip`, `remote_port`, `allowed_ips` labels.
- Kill the tunnel (or wait for a Proton drop) → `wireguard-handshake-stall` fires once `min(...)` has been > 300 s for 3 m (~8 min after the drop; the 2026-09-03 outage ran 21 min). Exporter death → `wireguard-exporter-down`.
- Thresholds were calibrated on the first ~15 min of live data plus the 2026-09-03 outage shape — revisit if Proton changes its failover-peer behaviour.

### References

- `docs/debug.md` §"Topology cheat sheet" and §"Planned fixes"
