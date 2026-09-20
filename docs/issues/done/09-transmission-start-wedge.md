# Transmission start-wedge after hypervisor shutdown (resolved 2026-09-19)

### Problem

2026-09-18: melon's hypervisor was shut down (~11:00 EDT). On the first boot after the unclean power-off, `transmission.service` wedged during startup — RPC bound, READY never signalled, SIGKILL after 90 s start + 90 s stop timeouts. Four start attempts over ~30 h wedged identically. With `Restart=no` and a `transmission-down` alert that could structurally never fire, it stayed down silently.

Full timeline: `docs/reports/2026-09-18-transmission-wedge.md`.

### Root cause (two stacked, both from the hypervisor shutdown)

1. **Path-MTU shrink.** The rebuilt underlay network couldn't carry the tunnel's 1420 B payloads. Control plane (handshakes ≤138 s) stayed healthy; big packets blackholed. Proved by in-ns probes: DNS ✓, TCP connect ✓, TLS ✗ at MTU 1420/1400, ✓ at **1300**. Fix: `MTU = 1300` on `proton0` (runtime-applied 2026-09-19; permanent entry in the WG config secret still pending — the next `proton.service` restart would revert it).
2. **Degraded CIFS session.** Every *uncached* metadata op on `/mnt/media` took ~2.5 s (cached: 24 ms; pumpkin pings at 0.16 ms). Transmission's startup serially loads ~4000 torrents and stats their files over CIFS — hours of work against a 90 s `TimeoutStartSec`. Proved by per-thread kernel stacks mid-wedge: `[cifs] wait_for_response → smb2_query_path_info → cifs_get_inode_info` holding 40–60 s, then completing (the daemon was crawling, never deadlocked). Fix: `systemctl restart mnt-media.mount` (fresh SMB session).

Systemic amplifiers: `Restart=no` (nixpkgs default), unset `TimeoutStartSec` (90 s default), and `transmission-down`'s `== 0` PromQL filter semantics (can never fire).

### Fixes applied (this repo)

- `generic/server/arr.nix` — `Restart=on-failure` + `TimeoutStartSec=600` on the transmission unit.
- `generic/server/visibility.nix` — `== 0` → `== bool 0` in `traefik-backend-down`, `traefik-down`, `alloy-down`, `transmission-down`, `wireguard-exporter-down`.
- `docs/debug.md` — new decoders (CIFS wait_for_response signature, stat-timing check, foreground-vs-sandbox bisection, per-thread stack forensics, traefik 499/502, echo-safe filters).

### Remaining follow-ups

1. **MTU permanence** — add `MTU = 1300` under `[Interface]` in `secrets/proton-vpn.age` (`agenix -e`), before the next proton restart/reboot.
2. **Pumpkin's metadata latency** — 2.5 s per cold stat is pathological (spun-down disks suspected). Bites every service walking `/mnt/media`; consider `actimeo=60` as a band-aid but fix the source.
3. **58 min 40 s initrd** on the Sep 18 boot — unexplained; investigate if it recurs.
4. **RPC-level watchdog** (`docs/issues/06-transmission-watchdog.md`) — the namegroup process count was 1 during every wedge; only an RPC health check would have caught the *hang*.

### References

- `docs/reports/2026-09-18-transmission-wedge.md`; `docs/debug.md` §Transmission specifics; `generic/server/arr.nix`, `generic/server/visibility.nix`; `docs/issues/06-transmission-watchdog.md`
