# Lidarr CPU spin — thread-pool starvation, boot-time contention engine

**Open.** Opened 2026-09-27. Mechanism identified 2026-11-02 (exportarr full queue-page enumeration at the 10 s global scrape interval — see below); durable fix (exportarr scrape interval + alert) still pending. Suspected aggravator of `docs/issues/done/10-forgejo-dependency-fail-after-reboot.md`.

### Problem

On the 2026-09-27 boot, `lidarr.service` came up with its process at ~1172% CPU, 11.1 G RSS, 310 tasks, logging "thread pool starvation"; it owns 488 of the 878 `database is locked` errors recorded in that boot's journal (Sonarr 169, grafana-start 128, navidrome 58, Radarr 26, Prowlarr 6, …). That SQLite/podman-boltdb contention storm is what killed `podman-forgejo-db`'s first post-boot run (exit 126) and also InfluxDB's and meilisearch-ui's first starts. Zero podman start failures in the 12 h before the reboot, so the storm is boot-specific — but it recurs on every boot until the spin source is fixed.

Contributing: `lidarr-search-drip.service` failed at 10:08:24 (exit 7, timer-triggered). The drip's curl had no `--max-time` at the time of that failure — the fix (`ade1d74`, `RuntimeMaxSec=1800` + `--max-time 60`) is now on master (in `generic/server/lidarr-search-drip.nix`) and in melon's 2026-09-27 11:48 switch generation; a 67 h runaway drip was documented on 2026-09-24. Note melon booted a 12-day-old closure on 09-27, so the fix wasn't live at that boot.

### Status update (2026-11-02)

The 2026-11-02 "Lidarr stuck on loading screen" outage reproduced this exact class outside a boot and identified the mechanism — it is **none** of the three suspects below. `prometheus-exportarr-lidarr-exporter` performs a **full Lidarr API collection on every Prometheus scrape** (every page of `/api/v1/queue` plus `/api/v1/artist`), and the global `scrape_interval = "10s"` applies to the exportarr job with no per-job override (`generic/server/visibility.nix`). While the queue is small this is the chronic lock-burst noise catalogued in `docs/debug/known-noise.md`; after the 2026-10-30 import storm grew the queue to ~2,740 items (**137 pages**), each sweep became 474–606 req/min through traefik, 315+ concurrent connections, Lidarr at 16+ GB RSS / ~345 threads, hourly `database is locked` counts of 420–851 (baseline ≤245), 284 `[Fatal] Request Failed` on `GET /api/v1/queue`, and `/api/v1/artist` at p50 1,289 s (baseline 1.4–4.7 s) — the SPA blocks on that call, hence the loading screen. `/ping` and uptime-kuma stayed green throughout, so nothing alerted. Stopping the exporter recovered the API within minutes (315→2 ESTAB, RSS 16.3→11.2 GB) without restarting Lidarr. Full timeline and evidence: `docs/reports/2026-11-02-lidarr-loading-screen.md`. Decoder: `docs/debug/lidarr.md`.

At boot the same storm recurs through the same path — every arr exporter sweeps a rebuilt queue while podman starts everything else; the 2026-09-27 contention pattern fits.

### To do

- ~~Merge `ade1d74` (lidarr drip `--max-time`) and deploy.~~ — done 2026-09-27: merged (ancestor of `2d01856`) and in melon's 09-27 switch generation.
- ~~Investigate the lidarr thread-pool starvation itself: is it the drip runaway, a bad indexer connection, or a `/mnt/media` CIFS stall (the 2026-09-18 mechanism)?~~ — **answered 2026-11-02: none of the three. It is exportarr-lidarr's full queue-page enumeration at the global 10 s scrape interval, saturating the API whenever the queue is large.**
- **Fix:** written in the working tree 2026-11-02, **pending deploy** — `generic/server/visibility.nix`: exportarr job `scrape_interval = "5m"` (was the global 10 s), all four `exportarr-*.url` → loopback ports (8686/8989/7878/9696, keeps the sweeps off traefik), and the `exportarr-scrape-down` alert (`up{job="exportarr"} == bool 0`, `for = "15m"` — the incident was invisible to all eight provisioned alerts).
- Re-examine after the next reboot whether boot-time `database is locked` storms subside (baseline: 878 errors this boot) — the exporter is currently **stopped** on melon post-2026-11-02, so the next boot test depends on the scrape-interval fix landing first.

### References

- `docs/reports/2026-09-27-forgejo-dependency-outage.md` §4.2
- `docs/reports/2026-11-02-lidarr-loading-screen.md`
- `docs/debug/lidarr.md`
- `generic/server/lidarr-search-drip.nix`
- `docs/issues/done/09-transmission-start-wedge.md` (CIFS metadata-stall precedent)
