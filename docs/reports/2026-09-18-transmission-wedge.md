# Transmission Boot-Wedge Outage Post-Incident Report — melon, 2026-09-18/19

- **Systems affected:** transmission (RPC + torrent traffic), lidarr/radarr/sonarr integrations, Uptime-Kuma monitors #5 "Transmission" and #30 "Arr"
- **Impact:** ~30 h of download-client unavailability (2026-09-18 17:24 EDT → 2026-09-19 ~21:50 EDT); no data loss; no torrents in flight
- **Onset:** 2026-09-18 ~11:00 EDT — melon's hypervisor was shut down (user-confirmed), killing the VM uncleanly
- **Recovery:** 2026-09-19 ~21:50 EDT — `systemctl restart mnt-media.mount` (fresh CIFS session) + `systemctl start transmission`; user-confirmed running
- **Status:** **resolved** — two stacked root causes, both environmental, both triggered by the hypervisor shutdown
- **Methodology:** Loki + Prometheus + Grafana via mcp-grafana MCP (three parallel investigation lanes per `docs/debug.md`), then live forensics on melon via SSH: in-namespace probes, foreground vs. sandboxed daemon runs with `--log-level=debug`, and per-thread `/proc/<pid>/task/*/stack` captures.

## 1. Executive summary

The hypervisor hosting melon was shut down at ~11:00 EDT on 2026-09-18. Two independent things broke in the aftermath, and they stacked:

1. **The underlay network path changed** (hypervisor network brought up differently), shrinking the path MTU below what the WireGuard tunnel assumed. The tunnel's *control plane* stayed healthy (handshakes ≤138 s for 2.5 days), but payload packets bigger than ~1360 B were blackholed — DNS worked, TCP connected, TLS handshakes died mid-flight. Fixed by lowering `proton0` MTU to 1300 (runtime; permanence pending in the WG config secret).
2. **The CIFS mount to pumpkin degraded.** Every *uncached* metadata op on `/mnt/media` took ~2.5 s (cached ones: 24 ms), and transmission's startup stats files for ~4000 torrents serially — an hours-long startup against a 90 s `TimeoutStartSec`. The daemon was never deadlocked: per-thread kernel stacks showed it blocked in `[cifs] wait_for_response → smb2_query_path_info`, crawling one stat at a time. Fixed by remounting the share (fresh SMB session).

Because `Restart=no` (default) and the `transmission-down` alert was structurally unable to fire (`== 0` PromQL filters instead of yielding), the wedge was **silent for ~30 hours**. Mitigations committed to the repo: `Restart=on-failure` + `TimeoutStartSec=600` on the unit, `== bool 0` fixes in five alert rules.

## 2. Timeline

All times EDT (UTC−4). Sources: Loki (journald), Prometheus, traefik access logs, direct SSH forensics.

| Time | Event | Source |
|------|-------|--------|
| **Sep 18 ~11:00** | Hypervisor shut down; melon killed uncleanly (journal stops, later `fsck: Dirty bit is set`) | user + journal |
| Sep 18 13:12:40 | Boot attempt #1: journald "system.journal corrupted or uncleanly shut down"; logs stop again after ~40 s | systemd-journald |
| Sep 18 14:00–16:00 | Zero journal lines — VM down | Loki |
| Sep 18 16:13:37 | Final boot: kernel starts (`node_boot_time_seconds` = 16:13:34) — after a **58 min 40 s initrd** (still unexplained) | kernel, node_exporter |
| Sep 18 17:13:16 | `proton.service`: "Waiting for wireguard endpoint... success!" | proton.service |
| Sep 18 17:13:22 | Transmission prestart runs; daemon starts | transmission |
| Sep 18 17:15:15 | `influxdb2.service: Failed with result 'timeout'` (same boot, unrelated) | systemd |
| Sep 18 **17:16:25** | `transmission.service: Failed with result 'timeout'` (90 s start + 90 s stop timeout → SIGKILL). Consumed: 613 ms CPU / 3 min, ~11 KB IP | systemd |
| Sep 18 17:24:08 | Kuma 'Transmission' `Failing: 502` — continuously ever since | uptime-kuma |
| Sep 19 20:41:04 | daniel: `systemctl start transmission.service` — wedge #2 (10.5 s CPU, 848 MB, 181.5 MB read, ~14 KB IP) | sudo, systemd |
| Sep 19 20:44:04 | SIGKILL, failed again | systemd |
| Sep 19 ~21:15–21:19 | In-ns probes: DNS ✓, TCP ✓, TLS ✗ (`unexpected eof`). MTU 1400 no help; **MTU 1300 → HTTPS works** — tunnel data plane restored | SSH probes |
| Sep 19 21:21:34 | Start attempt #3 — **wedges with a now-working tunnel** (12.2 s CPU, 31.9 MB read, 2.1/2.5 KB IP). Data plane exonerated as *the* wedge cause | systemd |
| Sep 19 21:38–21:40 | Foreground run (`nsenter --net` + `sudo -u transmission`, no sandbox): **healthy** — RPC binds in 25 ms, 4000 torrents resume, announces flow (first at t+43 s), downloads run | debug log |
| Sep 19 21:45–21:48 | Sandboxed run (real unit + `--log-level=debug`): **wedge reproduced**. Per-thread stacks: main in `futex_wait`, worker thread in **`[cifs] wait_for_response → smb2_query_path_info → cifs_get_inode_info`** for 40–60 s, then recovery at t+60 s | /proc stacks |
| Sep 19 ~21:50 | `systemctl restart mnt-media.mount` → fresh SMB session → `systemctl start transmission` → **up** | user |
| Sep 19 ~21:55+ | Kuma 'Transmission' Up; torrents seeding | uptime-kuma |

## 3. Scope of impact

**Broken:** transmission RPC (`transmission.brotherwolf.ca` via traefik → `localhost:9091` port mapping into the proton namespace), all torrent traffic, *arr download-client operations, kuma monitors #5/#30.

**Unaffected:** every other melon service (traefik, forgejo, jellyfin, immich, observability stack), the LAN, onion's exporters, host resources (CPU/memory/disk healthy), the VPN namespace itself.

## 4. Key evidence

### 4.1 Four identical wedges — but the unit only *looks* dead

All four start attempts showed the same systemd signature: ~5–6% CPU duty, modest disk reads, near-zero IP traffic, 90 s start timeout, ignored SIGTERM, SIGKILL. The daemon never crashed on its own and never logged an error (message-level 3).

### 4.2 The daemon is crawling, not deadlocked (per-thread stacks)

In the sandboxed run, thread 286840 sat for 40–60 s in:

```
wait_for_response+0xbe/0x120 [cifs]
compound_send_recv ... [cifs]
smb2_compound_op ... [cifs]
smb2_query_path_info ... [cifs]
cifs_get_fattr ... [cifs]
cifs_get_inode_info ... [cifs]
```

then completed and the daemon proceeded normally (new torrent-worker threads, peer sockets). Meanwhile the main thread waited in `futex_wait` (session handshake) — READY can only be sent after the whole load completes, so systemd's 90 s timer always won.

### 4.3 CIFS metadata latency: 24 ms cached vs 2.5 s uncached

`stat /mnt/media/downloads` = 24 ms (attr cache warm from node_exporter's minute tick); `stat /mnt/media/downloads/incomplete` = **2.557 s** (cold). Pumpkin pings at 0.16 ms — network fine; the mount (`active since` the post-event boot, 1 d 8 h old) had a degraded SMB session. This is why the earlier "CIFS ruled out" (via `node_filesystem_avail_bytes`, which only reads the warm root statfs) was wrong — see §5.

### 4.4 Tunnel control plane healthy throughout

`wireguard_latest_handshake_delay_seconds` ≤138 s for 2.5 days (dead threshold ~180 s); `proton-br` keepalives flat ~51 B/s tx / ~367 B/s rx; `up{job="wireguard"}` = 1. The 2026-09-03 signature was absent.

### 4.5 But the data plane *was* broken — a second, separate fault

In-ns probes: DNS resolved, TCP connected, TLS died (`unexpected eof` at MTU 1420 and 1400; works at **1300**). Classic path-MTU blackhole from the hypervisor network change: small packets (WG handshakes ~100 B, DNS, SYN) pass; payload packets >~1360 B don't. Fix: `MTU = 1300` (runtime-applied; permanent entry in the WG config secret is still pending).

### 4.6 Foreground-vs-sandbox bisection

Identical daemon, identical netns: without the unit's sandbox it starts and works in seconds; with the unit's sandbox it wedges. The sandbox itself is innocent — it merely holds the same bind-mounted CIFS the foreground run happened not to exercise in its first 90 s. The discriminating variable was *which CIFS paths get touched during startup*.

## 5. What was ruled out

| Hypothesis | Killing evidence |
|---|---|
| Dead Proton tunnel (2026-09-03 repeat) | Handshakes ≤138 s for 2.5 days; proton-br keepalives flat |
| Tunnel data plane as the *wedge* cause | Attempt #3 wedged after MTU 1300 had restored HTTPS through the ns |
| Start raced a namespace rebuild (2026-09-11 repeat) | proton.service settled before every start; zero proton activity in window |
| `nixos-rebuild switch` storm | 0 matching journal lines in 60 h |
| OOM / CPU starvation | `node_vmstat_oom_kill` = 0; ≥92% idle during attempts |
| **"CIFS is fine" (early ruling — REVISED)** | Early check used `node_filesystem_avail_bytes` (warm, statfs-level) and zero kernel CIFS errors. Wrong: per-file *metadata* ops were 2.5 s each — no kernel errors, just latency. Per-thread stacks proved it |
| Daemon deadlock (mutex/network) | Thread stacks: no futex deadlock, no connect/read block — a CIFS wait that *completes* |

## 6. Root-cause analysis

**Two independent environmental faults, both born from the hypervisor shutdown, stacked on top of two pre-existing systemic gaps.**

Mechanism chain:

1. **Unclean power-off** (hypervisor shutdown) → corrupted journal, double boot, 58-min initrd.
2. **Fault A — path-MTU shrink.** The rebuilt underlay network carried fewer bytes per frame than the tunnel assumed (1420). Control plane unaffected; payload blackholed. This is what killed the tunnel for torrent traffic and any large TLS/announce exchange (and what made the daemon's network activity look frozen).
3. **Fault B — degraded CIFS session.** The SMB session established at the post-event boot served every *uncached* metadata op at ~2.5 s. Transmission 4.1.3's startup serially loads ~4000 torrents and stats their files over `/mnt/media` — hours of work against a 90 s `TimeoutStartSec`. The daemon blocked in `wait_for_response [cifs]`, never reached READY, ignored SIGTERM (blocked main thread), and was SIGKILLed.
4. **Systemic gap 1 — no resilience.** `Restart=no` (nixpkgs default): one failed start = permanently down. `TimeoutStartSec` unset = 90 s, hopeless for a 4000-torrent session even on a healthy day.
5. **Systemic gap 2 — no observability.** `transmission-down` used `sum(...) == 0` — PromQL *filter* semantics (yields value 0, falsy to Grafana's evaluator; absent-series case fell to `no_data_state=OK`). The rule could never fire, so ~30 h of downtime produced no page.

**Recovery actions:** MTU 1300 on `proton0`; `systemctl restart mnt-media.mount` (fresh SMB session); `systemctl start transmission`.

**Confidence:** high for both faults (each directly observed and independently fixed) and for the systemic gaps; the only genuinely open question is *why* pumpkin serves metadata at 2.5 s (spun-down disks are the classic suspect) and the 58-min initrd.

## 7. Adjacent findings

1. **Five Grafana rules could never fire** — `== 0` filter semantics in `traefik-backend-down`, `traefik-down`, `alloy-down`, `transmission-down`, `wireguard-exporter-down`. Fixed to `== bool 0` in `generic/server/visibility.nix` (this change).
2. **Unit resilience fixes** — `Restart=on-failure` + `TimeoutStartSec=600` added to the transmission unit in `generic/server/arr.nix` (this change).
3. **`docs/debug.md` drift fixed** — namegroups claim, proton-br "100–800 B/s" figure, alert list; new decoders added (this change).
4. **MTU permanence pending** — `MTU = 1300` must go into `[Interface]` of `secrets/proton-vpn.age` (agenix rekey) or the tunnel breaks again on the next `proton.service` restart.
5. **`influxdb2.service` also failed with 'timeout' at the same boot** — self-recovered.
6. **58 min 40 s initrd** on the final boot — unexplained; worth `systemd-analyze blame` / initrd journal if it recurs.

## 8. Recommendations

1. **Make the MTU permanent** (secret edit, §7.4) — do this before the next reboot.
2. **Investigate pumpkin's metadata latency** (spun-down disks? samba config?) — 2.5 s per cold stat will bite every service that walks `/mnt/media`. Consider `actimeo=60` on the mount to amortize, but fix the source.
3. **Deploy the repo mitigations** (`Restart=on-failure`, `TimeoutStartSec=600`, `== bool 0` alerts) on the next switch.
4. **RPC-level watchdog** (`docs/issues/06-transmission-watchdog.md`) — process existence ≠ RPC health; the namegroup count was 1 during every wedge.
5. **Hypervisor shutdown procedure:** shut guests down gracefully before the hypervisor — an unclean kill of melon started this entire chain.

## Appendix — sources & methods

- **Loki** (journald export, `melon`): unit-filtered queries (`{unit="transmission.service"}`, `{unit="proton.service"}`), systemd text filters, kuma `MONITOR` transitions
- **Prometheus**: `wireguard_latest_handshake_delay_seconds`, `node_network_*{device="proton-br","ens3"}`, `node_boot_time_seconds`, `namedprocess_namegroup_num_procs`, `node_vmstat_oom_kill`, `node_filesystem_avail_bytes`, `min_over_time(up{...})`
- **Grafana**: rule normalization check (classic condition with raw query), traefik access-log 499/502 discrimination via `RouterName=transmission@file`
- **SSH forensics on melon** (read-only except user-run sudo scripts): `systemctl cat` (unit definition), in-ns probes (`nsenter --net=/run/netns/proton`), foreground run with `--log-level=debug`, sandboxed run via systemd drop-in, per-thread `/proc/<pid>/task/*/stack` + `wchan`, `stat` timings, `/proc/fs/cifs/DebugData`
- All timestamps converted UTC → EDT (UTC−4); journal MESSAGEs were already EDT

Follow-up issue: `docs/issues/done/09-transmission-start-wedge.md`; playbook updates: `docs/debug.md`.
