# Transmission Outage Post-Incident Report — melon, 2026-09-03

- **Systems affected:** transmission (RPC + torrent traffic), lidarr/radarr/sonarr integrations, Uptime-Kuma monitors #5 "Transmission" and #30 "Arr"
- **Impact:** ~21 min of download-client unavailability; no data loss; no service restart required
- **Onset:** 21:35 EDT (degrading), 21:42 EDT (fully down)
- **Recovery:** 21:56:55 EDT (self-healed)
- **Status:** resolved; root cause medium-confidence (see §6); follow-up issues filed in `issues/`
- **Methodology:** Loki + Prometheus via mcp-grafana MCP, plus read-only checks on melon. All evidence below is from these sources; each claim's source is noted.

## 1. Executive summary

At ~**21:35 EDT** Transmission's RPC endpoint began failing intermittently; by **21:42** it was fully unresponsive; it **self-recovered at 21:56:55 EDT** — ~21 minutes of downtime, no human intervention. Uptime-Kuma declared it down at 21:45:34 and fired a priority-8 Gotify notification; a "[✅ Up] 200 - OK" notification fired at 21:56:55.

The daemon **never crashed or restarted** (same PID since Aug 11). All evidence points to the **Proton VPN tunnel degrading and dropping** from ~21:30 to ~21:58, which froze Transmission 4.1.3's single-threaded session (a blocking announce/DNS operation through the dead tunnel) — and since the RPC server shares that thread, the Web UI and all *arr integrations timed out. When the tunnel returned, the blocked call completed and everything self-healed.

## 2. Timeline

All times EDT (UTC−4), 2026-09-03. Sources: Loki (journald) and Prometheus on melon.

| Time | Event | Source |
|------|-------|--------|
| 21:22:29 | Lidarr adds torrent (Aretha Franklin – *Lady Soul*, 24-96 FLAC) to Transmission — **works** | lidarr.service |
| 21:28–21:33 | VPN bridge (`proton-br`) keepalive rate drops from ~700–800 B/s to ~157 B/s — tunnel begins degrading | node_exporter |
| 21:35:37 | Lidarr: first `Unable to retrieve queue and history items from Transmission` | lidarr.service |
| 21:35:51 | Lidarr still able to add a torrent (*Respect And Other Hits*) — **RPC intermittently responsive** | lidarr.service |
| 21:39:35 | Lidarr adds another torrent (*Love All The Hurt Away*) — still working | lidarr.service |
| 21:41:40 | Uptime-Kuma HTTP check to `localhost:9091` times out (48 s timeout, logged 21:42:28 as Retry 1) — **RPC fully dead from here** | uptime-kuma |
| 21:42:55 | Lidarr: `DownloadClientUnavailableException: Unable to connect to Transmission` — repeats every ~3 min until 21:56:44 | lidarr.service |
| 21:43:11 / 21:43:38 | Same exception from Radarr and Sonarr | radarr/sonarr.service |
| 21:45:34 | Uptime-Kuma: Transmission **Failing** after 3 retries; Gotify alert `[Transmission] [🔴 Down]` | uptime-kuma, gotify |
| 21:45:58 | Kuma group monitor #30 "Arr" flips to Failing (child: Transmission) | uptime-kuma |
| 21:47:45 | `iperf3[4093845]: segfault … in ld-musl-x86_64.so.1` — the hourly iperf3-exporter test crashes (see §7.2) | kernel |
| ~21:46–21:56 | melon `ens3` traffic collapses: TX 13 KB/s, RX 36 KB/s (5-min averages) — all torrent traffic stopped | node_exporter |
| 21:53 | `proton-br` keepalives bottom out at ~36 B/s (vs ~750 B/s healthy) | node_exporter |
| 21:56:44 | Lidarr's last Transmission failure | lidarr.service |
| **21:56:55** | Kuma gets `200 OK`; Gotify fires `[Transmission] [✅ Up]` | uptime-kuma, gotify |
| 21:58–22:13 | `proton-br` keepalives and `ens3` traffic recover | node_exporter |
| 22:14–22:45 | `ens3` RX sustains 40–50 MB/s (~30 min) — Transmission catching up on the queued torrents (~80 GB) | node_exporter |

## 3. Scope of impact

**Broken (all recovered):**

- Transmission RPC (`localhost:9091` via the VPN-namespace port mapping) — the failure mode for everyone below
- Lidarr / Radarr / Sonarr — queue monitoring and (later) all download-client operations failed every ~3 min
- Uptime-Kuma monitors #5 "Transmission" and #30 "Arr" (group)
- Transmission's torrent traffic itself (seeding/downloading halted for the whole window)

**Unaffected:**

- LAN: Prometheus on melon scraped onion's five exporters (node/process/smartctl/nvidia/…) every 60 s for the entire window with zero misses — the LAN and melon↔onion path never flapped
- All other melon services (Grafana, Forgejo, Jellyfin, Loki, Tempo, …) logged nothing abnormal during the window
- The VPN *namespace* itself: `proton.service` and the namespace units were never reconfigured (no wg-quick/proton/nsenter journal entries)

## 4. Key evidence

### 4.1 The daemon wedged; it did not crash

`transmission.service` has been `active (running) since Aug 11` with Main PID 216328 — unchanged through the incident. No entries at all in its journal (message-level 3 logs errors; it logged none — it was **blocked**, not erroring).

### 4.2 Network collapse on melon (`node_network_*_bytes_total{device="ens3"}`)

5-minute rates: TX 2.5 MB/s at 21:43 → **0.013 MB/s at 21:48, 0.011 at 21:53** → 0.28 at 21:58 → 3.0 at 22:03. RX 1.0 MB/s at 21:44 → **0.036/0.035 at 21:49/21:54** → 7.3 at 21:59. Both directions went dead-silent during the outage and revived with the recovery — consistent with Transmission's torrent traffic (the dominant ens3 traffic) stopping because the session froze, then surging 40–50 MB/s at 22:14 as it cleared the backlog.

### 4.3 VPN bridge degradation (`node_network_transmit_bytes_total{device="proton-br"}`)

The bridge carrying the VPN namespace's traffic shows the only direct signature of the tunnel: ~700–814 B/s of keepalive chatter until 21:28, **157 B/s by 21:33**, drifting down to **36 B/s at 21:53**, then recovering through 21:58–22:13. This degradation envelope matches the RPC outage almost exactly.

### 4.4 System health during the outage was normal

`node_load1` stayed 5–9 and `node_memory_MemAvailable_bytes` ~12–13 GB through 21:42–21:56 — no CPU starvation, no OOM, no D-state pileup (which rules out a mass CIFS block).

## 5. What was ruled out

| Hypothesis | Evidence against |
|---|---|
| Service crash/restart | Unit up since Aug 11; PID unchanged |
| OOM / resource exhaustion | No OOM kills; load and memory flat during the outage |
| CIFS / pumpkin NAS stall | Zero CIFS/SMB kernel messages in 8 h (targeted kernel-journal query); no D-state load spike during the outage |
| LAN/switch/hardware failure | Onion scrapes at 60 s cadence never missed; melon's NIC link never flapped (no kernel link messages) |
| Firewall or systemd changes | No `systemd[1]` unit activity, no nft/firewall logs in the window |
| VPN namespace teardown | No proton/wg-quick/nsenter journal entries; namespace units untouched |
| General internet/DNS outage | Metar-exporter `EAI_AGAIN` errors look damning (failures at 21:40:39, 21:45:46, 21:50:49, 21:55:54) but are **constant background noise** — 8 per 10-minute bucket, all day, for 10 h straight. Not a signal. |
| The iperf3 test killing the network | The hourly exporter test at 21:47:45 segfaulted (see §7.2) but runs only ~seconds and cannot affect localhost RPC; also, the RPC died at 21:41:40, minutes before it ran |

## 6. Root-cause analysis

**Most probable cause: a Proton VPN tunnel outage (~21:28–21:58) that froze Transmission's single-threaded session.**

The mechanism chain:

1. **The tunnel died.** Proton's WireGuard endpoint became unreachable (server rotation/maintenance, or an upstream path blip). The `proton-br` keepalive collapse is the signature; Transmission is confined to that namespace (`vpnConfinement` in `generic/server/arr.nix`), so its *entire* world — trackers, peers, DNS for announce lookups — goes through the tunnel.
2. **The session thread blocked.** Transmission 4.1.3 runs torrent session, tracker announces, peer I/O, and the RPC server on **one libevent loop**. A tracker announce (or its DNS resolution) issued through the dead tunnel blocked without a timeout — blocked calls don't error, which is why message-level 3 logged nothing.
3. **The RPC froze.** With the session thread stuck, the RPC server on `192.168.15.1:9091` (VPN namespace) stopped accepting/processing — connections hang rather than refuse, exactly matching Uptime-Kuma's 48 s timeouts and the *arr `DownloadClientUnavailableException`s.
4. **Self-heal.** When the tunnel returned (~21:56–21:58), the pending operation completed, the loop unblocked, and Kuma got its 200 at 21:56:55. No restart, no intervention.
5. **Catch-up.** The freed session immediately raced through the queued work — hence the 40–50 MB/s RX sustained on ens3 from 22:14 to ~22:45 (~80 GB: the three Aretha albums plus Sonarr's MythBusters pack).

The intermittent phase (21:35–21:41) fits a *degrading* tunnel: queue GETs started timing out while small add-POSTs still slipped through, until the tunnel fully dropped at ~21:41.

**Confidence:** high for the *what* (daemon wedge, VPN-dependent) — the wedge is directly observed and all alternatives are ruled out; medium for the *where* (Proton tunnel vs. some other VPN-path component), because the VPN namespace itself is invisible to host exporters. One command on melon would confirm: `sudo ip netns exec proton wg show latest-handshakes` (handshake timestamps in the 21:30–22:00 window would show the drop). Follow-up issue to make this metric permanently visible: `issues/03-wireguard-handshake-exporter.md`.

## 7. Adjacent findings (unrelated to the outage, but worth attention)

1. **`iperf3-exporter` is broken.** The hourly Prometheus scrape (`scrape_interval = "1h"`, targets cucamelon/onion/pumpkin, `generic/server/visibility.nix`) crashed mid-test at 21:47:45 — `segfault … in ld-musl-x86_64.so.1` (kernel log). The `ghcr.io/edgard/iperf3_exporter` image appears to have a musl bug. Hourly speed metrics aren't being collected. Issue: `issues/04-iperf3-exporter-segfault.md`.
2. **Recurring load spikes on melon** — load 42 at 15:37, ~25 at 20:31–20:34, **90 at 21:09–21:14**, ~16 at 22:30–22:33. These correlate with media-library activity over CIFS (the MythBusters pack import; ~300 Mbps combined on ens3 at 21:09–21:24). The 22:30 spike was strong enough to make Grafana and Lidarr return 503s for ~1 min (Kuma monitors #4/#17). Transmission was fine during these spikes — they're a separate recurring issue, likely CIFS-copy storms.
3. **Sonarr import duplication.** At 21:16 Sonarr repeatedly hit `DestinationAlreadyExistsException` importing the MythBusters pack (all 14 seasons already present) — it's re-processing a pack it already imported.
4. **Long-broken exporters** (pre-existing, constant in logs): statuspage-exporter (context-deadline errors every ~10 s, up=0), metar-exporter (`EAI_AGAIN` on every poll), unpoller (401 vs. radish), shelly (401), copyparty on pumpkin (down), cucamelon exporters (down — laptop offline). None related to this incident, but they're noise that hides real signals. Issue: `issues/05-clean-up-broken-exporters.md`.
5. **Lidarr SQLite contention** at 21:45:10–11 (`database is locked`) — transient, from exportarr hammering the API during its minute tick; not related.

## 8. Recommendations

1. **Watch the tunnel, not just the service.** The outage was invisible to everything except the daemon's behaviour. A wg-handshake-age exporter plus Grafana alert is the fix (issue 03). Proton server rotations make this a recurring risk.
2. **Add a watchdog with teeth.** Kuma detected this (that's how you knew), but nothing acts. A systemd timer that restarts `transmission.service` when the RPC is down >5 min would shorten outages like this to ~1 min after the tunnel returns (issue 06).
3. **Pin or replace the iperf3-exporter image** and verify the hourly scrape actually completes (issue 04).
4. **Investigate the CIFS import storms** (load 90 at 21:09; 503s at 22:30) — consider throttling Sonarr/Lidarr import concurrency or scheduling heavy imports.
5. **Clean up the dead exporters** so future incidents don't drown in false signals (issue 05).
6. **Deploy the Alloy journal pipeline fix** so `unit` becomes a real Loki label — future investigations get ~100× cheaper (issue 01).

## Appendix — sources & methods

- **Loki** (journald export, `melon`): lidarr/radarr/sonarr/uptime-kuma/gotify/kernel units around 01:05–02:05 UTC (21:05–22:05 EDT); targeted line filters on the journald JSON (`_SYSTEMD_UNIT`, `SYSLOG_IDENTIFIER`)
- **Prometheus**: `up{instance=~"onion.*"}` (LAN health), `node_load1` / `node_memory_MemAvailable_bytes` (melon health), `node_network_*{device="ens3","proton-br"}` (traffic), `up{job="domain"}` (external probes)
- **Direct checks on melon** (read-only): `systemctl status transmission`, unit list for the proton namespace
- All 2026-09-04 01:xx UTC timestamps converted to EDT (UTC−4)

Follow-up issues: `issues/01`–`issues/06`; AI debugging playbook: `docs/debug.md`.
