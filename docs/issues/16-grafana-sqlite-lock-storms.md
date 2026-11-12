# Grafana SQLite lock storms — periodic `SQLITE_BUSY` bursts, 503s, `/-/ready` 500s

**Open.** Opened 2026-11-12. Pre-existing recurring condition; largest episode to date 2026-11-12 17:56–18:05 EST (~450 s continuous `grafana@file` traefik backend-down). Self-recovers; `sudo systemctl restart grafana` clears an episode.

### Problem

Grafana 13.0.12 on melon runs on the module-default SQLite (`/var/lib/grafana/data/grafana.db`) on the box's single **rotational 500 G HDD** (vda ROTA=1). Periodically it enters `SQLITE_BUSY` write-lock storms: journal lines `Failed getting data source err="database is locked (5) (SQLITE_BUSY)"`, alert-rule evaluation failures, alert-state persist retries up to 45–65 s, kvstore / unified-storage job-driver failures. `/api/health` returns Grafana's own DB-health 503 — body `{"database":"failing","version":"13.0.12","commit":"NA"}` (verified on direct loopback, not a traefik 503) — `/-/ready` 500s, so traefik marks the `grafana@file` backend down and MCP tools 503. `up{job="grafana"}` stays 1 through the storm (the /metrics endpoint doesn't touch the DB; up=0 only during actual switch restarts). Host is otherwise unconstrained (disk 63 %, 27 GiB mem avail, CPU ≤16 % during the storm). Chronic baseline: `database is locked` lines/day 7,242 (Nov 03), 24,641 (Nov 04), 5,962 (Nov 06), 549 (Nov 11), 920 (Nov 12); the 2026-11-12 episode (17:56–18:05 EST, ~639 lock lines, individual writes blocking 45–65 s) was the densest since early November. uptime-kuma monitor "Grafana" went Pending 17:58:09 → Failing 18:02:46 → recovered ~18:05.

The 2026-11-12 episode began 47 min after the rtorrent/flood switch (`72ace53`) and is **not** caused by it: the pre-switch process was already logging `SQLITE_BUSY` at 17:05 EST, the two new alert rules are field-identical to the existing nine and cannot break provisioning, and no grafana-adjacent config changed. The switch restart did produce a normal ~2 min startup window at 17:07–17:10 EST — distinct from the storm. Alert evaluations (`rtorrent-*` included) are casualties of the lock, not causes.

Recurring mentions in reports: 2026-10-21 (audiomuse phase transition), 2026-10-25 (konnected schema drift), 2026-11-03 (kvm pause), 2026-09-11 (switch storm), 2026-09-03 (load-induced). This is the same class as the lidarr SQLite-lock contention (`docs/issues/11-lidarr-cpu-spin.md`) but Grafana-internal.

### To do

- **Durable fix:** migrate Grafana storage to PostgreSQL (already running on melon for forgejo/audiomuse) — `services.grafana.settings.database` in `generic/server/visibility.nix` + a provisioned database. This is the standard remedy for SQLite write-lock storms, especially on a rotational disk.
- **Cheaper interim tuning (once root-confirmed):** `settings.database.max_open_conn = 1` and `locking_attempt_timeout_sec > 0` in `services.grafana.settings` (grafana has no DB tuning today); disable the permanently unhealthy provisioning repository.
- Diagnose the write path that saturates the lock (needs a root one-shot, `docs/debug.md` §Workflow rules): `ls -lh /var/lib/grafana/data/grafana.db*` (WAL size), `sqlite3 -readonly PRAGMA journal_mode` / `page_count` / `freelist_count`, table sizes (`annotation`, `alert_history`, unified-storage `resource` tables), and `lsof` on the db during a storm to name the long write transaction. Candidate contributors: ngalert state writes + unified-storage job/lease cleanup + `resource_version` updates.
- Add a sustained-outage signal so this class alerts instead of hiding behind the known-flap framing: `min_over_time(traefik_service_server_up{service="grafana@file"}[5m]) == bool 0`, plus watch `grafana_http_request_duration_seconds_count{status_code=~"5.."}`. The `changes()`-based flap check in `docs/debug/known-noise.md` cannot distinguish this (2026-11-12 episode: 7 changes/6 h — below chronic — but a 450 s continuous zero vs the 80 s 24 h max).

### References

- `docs/debug/known-noise.md` (grafana flap entry; lock-storm bullet added 2026-11-12)
- `docs/reports/2026-10-21-audiomuse-phase-transition.md` (first documented remedy: restart grafana)
- `docs/reports/2026-11-03-kvm-pause-dependency-cancel.md` (transient 503, self-recovered)
- `docs/issues/11-lidarr-cpu-spin.md` (SQLite contention class, arr-side)
- `generic/server/visibility.nix` (grafana config; no database override = SQLite default)
