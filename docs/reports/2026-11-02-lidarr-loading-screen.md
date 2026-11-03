# Lidarr loading screen — exportarr queue-enumeration saturation — 2026-11-02

- **Systems affected:** `lidarr.service` on melon (API starvation, UI stuck on the loading screen); `prometheus-exportarr-lidarr-exporter` (the load source; its Prometheus target dead from 16:07 EST); `lidarr-search-drip` (collateral: one failed run); uptime-kuma monitor #17 (green throughout — never caught it)
- **Impact:** the Lidarr UI was unusable (SPA shell loads, `GET /api/v1/artist` hangs ~20 min; user's browser aborted after 298 s and 461 s). 284 `[Fatal] Request Failed` API errors (nearly all `GET /api/v1/queue`) clustered 15:49–16:12 EST; one drip run failed on 60 s timeouts. No data loss — imports continued throughout (1,350 albums imported that day).
- **Onset:** 2026-11-01 15:49 EST (API scrape duration leaves the 3.7–4.3 s baseline); collapse 2026-11-02 13:00–16:00 EST (SQLite lock storm); user-visible from 19:33 EST
- **Recovery:** stopped `prometheus-exportarr-lidarr-exporter` (user ran `/tmp/lidarr-relief.sh` on melon) the evening of 2026-11-02; verified recovered within minutes: 315→2 ESTAB connections to `:8686`, Lidarr RSS 16.3→11.2 GB, API probe 37 ms. Lidarr never restarted (`NRestarts=0`).
- **Status:** resolved (recovered + mechanism identified). Durable fix pending — exportarr scrape interval + alert, tracked in `docs/issues/11-lidarr-cpu-spin.md`.
- **Methodology:** four parallel lanes (Journal/Loki, Prometheus, config/state, local SSH state) + one live verification pass. All times local (UTC−4 through 2026-11-01 02:00, UTC−5 after) unless noted.

## 1. Executive summary

A bulk import storm (started 2026-10-30 03:41, 1,843 albums by Nov 2) grew Lidarr's download queue to ~2,740 items — **137 pages**. `exportarr-lidarr` performs a *full* Lidarr API collection on every Prometheus scrape: every page of `/api/v1/queue` plus `/api/v1/artist`. The global `scrape_interval = "10s"` applies to the exportarr job with no per-job override (`generic/server/visibility.nix`), and exportarr exposes no collector-disable flags — so each collection is 137 queue-page calls through traefik plus the 1.8 MB artist payload, 474–606 requests/min, holding 315+ concurrent connections to `127.0.0.1:8686`.

At that scale the chronic lock-burst noise became the outage: a SQLite lock storm (420–851 `database is locked`/h vs ≤245 baseline) ran 13:00–16:00 EST, producing 284 `[Fatal] Request Failed` on `GET /api/v1/queue`. The lock storm subsided (0 after 18:00) but the request pileup was by then self-sustaining: Lidarr kept answering (`origin=200`) at 20+ min latencies. The SPA — which blocks on `GET /api/v1/artist` before leaving its loading screen — therefore hung, and the user's browser aborted with traefik 499s at 298 s and 461 s.

The failure was silent by design: traefik's `/ping` healthcheck is a light endpoint that stayed green (1.6 ms), uptime-kuma never fired Failing, and none of the eight provisioned alerts watches `up{job="exportarr",instance="localhost:9710"}` (dead from 16:07 EST) or `lidarr_scrape_duration_seconds` (avg 8.52 s, 2.7× baseline). Stopping the exporter drained the backlog within minutes — no Lidarr restart needed.

## 2. Timeline

| Time (local) | Event | Source |
|------|-------|--------|
| 2026-10-30 03:41 | Import storm begins (first import in window); 1,843 albums imported by Nov 2, 1,350 of them on Nov 2 | journal |
| 2026-11-01 15:13 | `podman-mixarr` starts (195 req/24 h — ruled out as load source) | systemd |
| 2026-11-01 15:49 | Lidarr API scrape duration leaves the 3.7–4.3 s baseline (degradation onset) | Prometheus |
| 2026-11-02 03:01 | First isolated exportarr-lidarr scrape failure | Prometheus |
| 09:35, 10:19 | uptime-kuma single-probe 503s (auto-recovered) | Loki |
| 12:11–12:25 | `lidarr_queue_total{status="downloadClientUnavailable"}` = 1,022–1,053; delay queue grows 1,078→1,348 by 16:08 | Prometheus |
| **13:00–16:00** | **SQLite lock storm: 420–851 `database is locked`/h vs ≤245 baseline** | Loki/journal |
| 15:49–16:12 | 284 `[Fatal] Request Failed`, nearly all `GET /api/v1/queue` | journal |
| 16:07 | exportarr-lidarr target permanently `up=0` in Prometheus (scrape deadline) | Prometheus |
| 16:10–16:25 | traefik latency for `lidarr@file` climbs 0.5→2.2→6.2→11.6 s | Prometheus |
| 16:22–16:24 | `lidarr-search-drip` fails: curl exit 28, three 60 s timeouts on `/api/v1/wanted/missing` | journal |
| 19:33–19:51 | User opens Lidarr: `/api/v1/artist` aborts after 298 s and 461 s (traefik 499, client `.188`) → loading screen | Loki |
| ~20:19 | `/api/v1/artist` p50 1,289 s (last 50 exportarr calls); 320 ESTAB to `:8686`; RSS 16.4 GB; exportarr still enumerating pages 1–137 | ssh, Loki |
| 20:25 | Verified live: exportarr fanning out multiple queue pages per second, 315 ESTAB | ssh |
| evening | Exporter stopped (`/tmp/lidarr-relief.sh`); verified recovered: 315→2 ESTAB, RSS 16.3→11.2 GB, API probe 37 ms (401 = auth layer, i.e. responsive) | ssh |

## 3. Root causes and fixes

| # | Root cause | Fix | Where |
|---|-----------|-----|-------|
| 1 | exportarr-lidarr does a full API collection (every queue page) on every Prometheus scrape; the global `scrape_interval = "10s"` applies with no per-job override and exportarr has no collector-disable flags. With a 137-page queue: 474–606 req/min through traefik, 315+ concurrent connections, thread-pool + sqlite saturation | **Pending:** per-job `scrape_interval` (≥60 s; 5 min is plenty) for the exportarr job in `generic/server/visibility.nix`; optionally `url = "http://127.0.0.1:8686"` to bypass traefik | working tree fix not yet applied; tracked in `docs/issues/11-lidarr-cpu-spin.md` |
| 2 | Queue ballooned to ~2,740 items (137 pages) during the 2026-10-30 import storm, making each sweep 2–3× costlier — pushed lock bursts from noise into outage | Background (user's bulk import), not a fault; ~1,000 items sat in `downloadClientUnavailable` at 12:11–12:25 EST, so part of the queue is also stalled | — |
| 3 | Silent by design: `/ping` and uptime-kuma stay green through API starvation; no alert watches `up{job="exportarr",instance="localhost:9710"}` or `lidarr_scrape_duration_seconds` — all eight provisioned alerts were normal throughout | **Pending:** alert on sustained exportarr-lidarr scrape failure, or `lidarr_scrape_duration_seconds > 8` (mind the `== bool 0` gotcha in `docs/debug/prometheus.md`) | — |
| 4 | `docs/debug/known-noise.md` framed arr lock bursts as unconditional minute-tick noise; the interval wording was stale (10 s) and the noise verdict had no queue-size qualifier | Corrected; `docs/debug/lidarr.md` decoder added | this report |

### Ruled out

- Lidarr crash/restart — `NRestarts=0`, active since Oct 8 21:40
- Disk full — 168 GB free on `/` (holds `/var/lib/lidarr`); `/mnt/media` 11 TB free
- OOM — 0 oom-kills, 13.5 GB MemAvailable at worst
- Traefik route/backend down — `/ping` 200 in 1.6 ms, root 302 in 175 ms through the public URL
- CIFS stall — timed `stat`/`ls` on `/mnt/media/music` 8–55 ms
- Other arr apps — sonarr/radarr/prowlarr scrape durations flat and `up` ≈ 0.999 throughout
- mixarr/blunderbase/maia — mixarr 195 req/24 h with its own timeouts (victim); blunderbase/maia are chess services (`/health` only)

### Key evidence

```
# exportarr flood, live on melon (20:25:57 EST — several pages in the same second):
Sending HTTP request {"url": "https://lidarr.lc.brotherwolf.ca/api/v1/queue?page=68"}
Sending HTTP request {"url": "https://lidarr.lc.brotherwolf.ca/api/v1/queue?page=11"}
Sending HTTP request {"url": "https://lidarr.lc.brotherwolf.ca/api/v1/queue?page=81"}
Sending HTTP request {"url": "https://lidarr.lc.brotherwolf.ca/api/v1/queue?page=26"}

# The loading screen, from traefik logs (user = 10.8.8.188, zero 503s ever):
GET /api/v1/artist  → 499  Duration 298.4 s   (19:38:47 → 19:43:45)
GET /api/v1/artist  → 499  Duration 461.3 s   (19:43:45 → 19:51:26)

# Lock storm hourly counts (baseline ≤245/h):
13:00 420 | 14:00 851 | 15:00 750 | 16:00 782 | 17:00 95 | 18:00+ 0

# Exportarr target death (265 zero-minutes today vs 4 the prior day):
count_over_time((up{job="exportarr",instance="localhost:9710"}==0)[24h:1m])
```

## 4. Follow-ups

- **Docs done:** `docs/debug/lidarr.md` decoder + topic-table row; `docs/issues/11-lidarr-cpu-spin.md` updated (its open investigation question is answered); `docs/debug/known-noise.md` corrected (10 s interval + queue-size qualifier); `docs/debug/planned-fixes.md` updated.
- **Repo fix:** written in the working tree 2026-11-02, pending deploy — `generic/server/visibility.nix`: exportarr job `scrape_interval = "5m"`, `exportarr-lidarr.url` → `http://127.0.0.1:8686`, `exportarr-scrape-down` alert (§3 rows 1 and 3).
- **Exporter state:** `prometheus-exportarr-lidarr-exporter` is currently **stopped** on melon — exportarr-lidarr metrics will be absent (`up=0`) until re-enabled; re-enable only after the scrape-interval fix, or the next big queue re-triggers this.
- **Queue hygiene (optional):** the ~2,740-item queue and the ~1,000 `downloadClientUnavailable` items predate and outlive the incident; worth a look in the Lidarr UI now that it's responsive.
