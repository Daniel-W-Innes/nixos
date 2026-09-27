# Known noise — ignore, don't chase


These are constant background noise and will burn queries if treated as signals (baseline first, see `docs/debug.md` §Workflow rules):

- **`podman-statuspage-exporter`** — "context deadline exceeded" errors every ~10 s, all day. Broken exporter, up=0.
- **`podman-metar-exporter`** — `socket.gaierror: [Errno -3] Try again` on every poll (~8 lines / 10 min, constant). Broken DNS in the container. NOT a network-health signal.
- **kernel `[TTM] Buffer eviction failed`** — every ~15 s (amdgpu VRAM). Floods kernel queries; always add a second filter when querying kernel lines.
- **`prometheus-unpoller-exporter`** — 401 vs radish, nil-pointer panics.
- **`prometheus-shelly-exporter`** — 401 Unauthorized every scrape.
- **`*arr` services** — `SQLite error (5): database is locked` bursts (exportarr contention at each minute tick), Prowlarr 429s from indexers.
- **postgres** — immich/postgres collation-version warnings.
- **grafana** — provisioning-repository "branch protection check" warnings.
- **loki.service** — logs its own queries (`caller=metrics.go`). Any broad regex matches your own query text; expect and discard these lines. Echo-safe filters exist: Loki logs the query URL-encoded, so a literal `@` in your filter can't match its own echoes (`@` → `%40` in the logged URL) — keying on a label value like `|= "transmission@file"` excludes all self-echoes (learned the hard way 2026-09-19, when "late 200s after the SIGKILL" were Grafana's own query echoes). A `count_over_time` baseline of your own filter string gets inflated by these echoes too — append `!= "caller="` to the selector (2026-09-27: a `|~ "Failed to start podman-"` baseline read 6 with echoes, 0 after).
- Broken scrape targets (up=0, pre-existing): `copyparty` (pumpkin:30266), `unpoller`, `shelly`, `statuspage`, all `cucamelon.*`.

