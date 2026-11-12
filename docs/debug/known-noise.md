# Known noise — ignore, don't chase


These are constant background noise and will burn queries if treated as signals (baseline first, see `docs/debug.md` §Workflow rules):

- **`podman-statuspage-exporter`** — "context deadline exceeded" errors every ~10 s, all day. Broken exporter, up=0.
- **`podman-metar-exporter`** — `socket.gaierror: [Errno -3] Try again` on every poll (~8 lines / 10 min, constant). Broken DNS in the container. NOT a network-health signal.
- **kernel `[TTM] Buffer eviction failed`** — every ~15 s (amdgpu VRAM). Floods kernel queries; always add a second filter when querying kernel lines.
- **`prometheus-unpoller-exporter`** — 401 vs radish, nil-pointer panics.
- **`prometheus-shelly-exporter`** — 401 Unauthorized every scrape.
- **`*arr` services** — `SQLite error (5): database is locked` bursts (exportarr contention on its **10 s** scrape — the global `scrape_interval` is 10 s with no per-job override; the old "minute tick" wording was stale), Prowlarr 429s from indexers. Noise only while the queue stays small: with a 100+ page queue, exportarr's full queue-page enumeration becomes the outage mechanism itself — `docs/debug/lidarr.md` (2026-11-02 loading-screen incident).
- **postgres** — immich/postgres collation-version warnings.
- **grafana** — provisioning-repository "branch protection check" warnings.
- **loki.service** — logs its own queries (`caller=metrics.go`). Any broad regex matches your own query text; expect and discard these lines. Echo-safe filters exist: Loki logs the query URL-encoded, so a literal `@` in your filter can't match its own echoes (`@` → `%40` in the logged URL) — keying on a label value like `|= "transmission@file"` excludes all self-echoes (learned the hard way 2026-09-19, when "late 200s after the SIGKILL" were Grafana's own query echoes). A `count_over_time` baseline of your own filter string gets inflated by these echoes too — append `!= "caller="` to the selector (2026-09-27: a `|~ "Failed to start podman-"` baseline read 6 with echoes, 0 after).
- **`grafana@file` traefik backend health-check flapping** — chronic isolated 0 samples (`changes(traefik_service_server_up{service="grafana@file"}[6h])` ≈ 48–82), each causing intermittent HTTP 503s to Grafana/MCP for ~60–90 s. The grafana process itself never restarts (`up{job="grafana"}` = 1). NOT a forgejo/backend-down signal. `lidarr`/`prowlarr`/`gotify` backends blip occasionally the same way (distinct from the exportarr queue-flood stall in `docs/debug/lidarr.md` — that one keeps `server_up=1` and `/ping` green the entire time).
- **`grafana` SQLite lock storms** — periodic `SQLITE_BUSY` bursts (`err="database is locked (5) (SQLITE_BUSY)"` in grafana's journal; `/api/health` 503s and `/-/ready` 500s from Grafana itself, not traefik). Pre-existing recurring (tens–hundreds of events/hour on many days); the 2026-11-12 episode was the largest (~450 s continuous `grafana@file` down, 17:56–18:05 EST) and self-recovered. `sudo systemctl restart grafana` clears an episode. `up{job="grafana"}` stays 1 through these (up=0 only during actual switch restarts) — distinguish a storm from the chronic flap with `min_over_time(traefik_service_server_up{service="grafana@file"}[5m]) == bool 0`; `changes()` can't (7 changes/6 h during the 2026-11-12 episode — below chronic). Durable fix: postgres migration — `docs/issues/16-grafana-sqlite-lock-storms.md`.
- Broken scrape targets (up=0, pre-existing): `copyparty` (pumpkin:30266), `unpoller`, `shelly`, `statuspage`, all `cucamelon.*`.

