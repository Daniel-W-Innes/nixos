# Forgejo Stranded After Reboot — Post-Incident Report — melon, 2026-09-25 → 09-27

- **Systems affected:** forgejo (+ `forgejo-db` podman postgres), gitea-runner-melon / gitea-runner-onion (CI); uptime-kuma monitors for git / meilisearch / bookorbit / media going Failing
- **Impact:** `git.lc.brotherwolf.ca` down ~39.5 h (2026-09-25 19:32 EDT → 2026-09-27 11:05 EDT); CI runners down the same period (melon's runner: 56,807 crash-loop restarts before the 09-27 reboot); **no data loss** (postgres recovered automatically after an unclean shutdown this boot)
- **Onset:** 2026-09-25 19:32 EDT (start-job dependency failure at the 19:25 reboot)
- **Recovery:** forgejo active 11:05:13 EDT 2026-09-27 (manual `systemctl start` via `/tmp/forgejo-recovery.sh`); melon runner still needs `reset-failed` + start (start-limit-hit from the crash-loop)
- **Status:** resolved; config fix implemented (`generic/server/forgejo.nix`, uncommitted, deploy pending) — `docs/issues/10-forgejo-dependency-fail-after-reboot.md`
- **Methodology:** Loki + Prometheus via the mcp-grafana MCP (four parallel lanes: journal timeline, metrics, repo config, live SSH state), plus one independent verification pass. All times EDT (UTC−4).

## 1. Executive summary

Two clean, user-initiated reboots of melon (2026-09-25 19:25 and 2026-09-27 10:04 — the second via `sudo systemctl reboot`) each produced the identical, invisible failure:

1. At boot, podman recreates all containers at once. In the resulting contention, the first `podman-forgejo-db` run died: conmon couldn't write the container exit file (ENOENT) and podman's own state save hit boltdb `database is locked` → the unit failed with exit 126 after 5m37s of wall time.
2. `forgejo.service` declares `Requires=podman-forgejo-db.service`, so the DB unit's failure cancelled forgejo's start job: `Job forgejo.service/start failed with result 'dependency'`.
3. **systemd never re-queues a dependency-failed job** — `Restart=always` only covers a running process exiting. When the DB's own `Restart=` recovered 22 s later (09-27; ~2 min on 09-25), nothing re-triggered forgejo. It stayed down until manually started: ~39.5 h.

The 2026-09-11 fix (psql wait-loop `mkBefore` the migrate + `TimeoutStartSec=600`) was deployed and did its job — but it only guards a *slow* DB, not a DB *unit* that fails outright. Same symptom class, new mechanism.

Why it was invisible: the `traefik-backend-down` alert had been firing since 09-25 ~19:35, but Grafana restarted with the 09-27 reboot and re-stamped `activeAt` to 10:18 — a 39.5 h outage presented as a 3-minute one.

## 2. Timeline

All times EDT (UTC−4), 2026-09-25 and 2026-09-27. Sources: Loki (journald), Prometheus, live SSH state.

| Time | Event | Source |
|------|-------|--------|
| 09-25 19:11:30 | forgejo stopped cleanly (SIGTERM) — last requests served | forgejo[1818126] |
| 09-25 19:25 | melon reboots (graceful; boot -1) | node_boot_time_seconds, journal |
| 09-25 19:32:28–31 | `podman-forgejo-db` first boot run fails (same signature as 09-27: boltdb/exit-file); forgejo start job cancelled: `Job forgejo.service/start failed with result 'dependency'` | systemd |
| 09-25 19:33 | DB's `Restart=` succeeds; postgres healthy for the next 38 h — **forgejo never starts** | podman-forgejo-db.service |
| 09-25 19:35 | `traefik_service_server_up{service="git@file"}` = 0 (continuous until recovery); runners begin 503 crash-loop | Prometheus, runner journals |
| 09-26 02:00 | `forgejo-dump.service` runs fine against the healthy DB — the DB was never the problem | journal |
| 09-27 09:39 / 09:56 | onion, cucamelon reboot (staggered ~17 / ~10 min — deliberate per-host reboots, not a power event) | node_boot_time_seconds |
| 09-27 10:03:54 | `daniel` runs `sudo systemctl reboot` on melon | sudo log |
| 09-27 10:04:04 | logind "The system will reboot now!"; ordered stops; "Reached target System Reboot" 10:05:38 | logind |
| 09-27 10:05:52 | melon kernel up; boots 12-day-old closure `nixos-system-melon-26.05.20260915.b67c7a6` — no switch, no new generation (newest on disk: system-368, 09-19) | journal, /run/current-system |
| 09-27 10:08:17–50 | `podman-forgejo-db` start; image pull 10:08:27; container create `f2b9600c` 10:08:50 | podman-forgejo-db.service |
| 09-27 10:08:24 | `lidarr-search-drip.service` fails (exit 7); lidarr spinning ~1172% CPU / 11.1 G RSS, "thread pool starvation" | systemd, ps |
| 09-27 10:08:32–41 | traefik 502s on `git@file`, then ejects the backend → 503s | traefik |
| 09-27 10:10:15 / 10:13:58 | InfluxDB and meilisearch-ui containers also fail their first post-boot start (podman-level contention; 878 `database is locked` errors across containers this boot, 0 in the 12 h before) | systemd |
| 09-27 10:11:11 | conmon: exit-file ENOENT for `f2b9600c` | journal |
| 09-27 10:12:18 | podman removes container + boltdb `database is locked` on state save → **exit 126** | podman-forgejo-db.service |
| 09-27 10:13:55 | `podman-forgejo-db` Failed ('exit-code', 1.047s CPU over 5m37s wall); forgejo start job cancelled 'dependency' | systemd |
| 09-27 10:14:17 | DB `Restart=` succeeds (22 s later) — nothing re-queues forgejo | systemd |
| 09-27 10:15:40–57 | postgres unclean-shutdown recovery; ready 10:15:57 | forgejo-db logs |
| 09-27 10:17:34 | kuma back up; Forgejo Server 503 pending 10:17:41; Failing cluster 10:20:41–55 (forgejo 503, meilisearch 502, bookorbit 502, media group, runner) | uptime-kuma |
| 09-27 10:18 | `traefik-backend-down` `activeAt` re-stamps (Grafana restart artifact — the outage was 38 h old) | Grafana |
| 09-27 11:04:49 | recovery script run: `systemctl start forgejo` | /tmp/forgejo-recovery.log |
| 09-27 11:05:13 | **forgejo active**; `Declare` 200s landing; melon runner start refused (start-limit-hit, pending reset) | systemd, forgejo router |
| 09-27 11:07 | `traefik_service_server_up{service="git@file"}` = 1 verified | Prometheus |

## 3. Scope of impact

**Broken (all recovered):**

- forgejo + `git.lc.brotherwolf.ca` — ~39.5 h (09-25 19:32 → 09-27 11:05), including all CI: melon's runner crash-looping the whole time (56,807 restarts by 09-27 09:55 ≈ 2.44 s/restart), onion's runner 503ing but alive
- Transient (~1 min each, 09-27 boot): InfluxDB and meilisearch-ui containers (first-start failures, recovered on retry)
- kuma monitors for git / meilisearch / bookorbit / media going Failing during both post-boot windows

**Unaffected:**

- Data: postgres restarted from the existing data dir after automatic unclean-shutdown recovery; forgejo's migration ran clean on the manual start
- The observability stack: journal stream intact throughout — this report was written entirely from Loki/Prometheus + read-only SSH
- All other `@file` backends (gotify, grafana, loki, prometheus, jellyfin, arrs) — only `git@file` was 0

## 4. Key evidence

### 4.1 The dependency chain (verbatim, 09-27 boot)

```
2026-09-27T10:13:55-04:00 melon systemd[1]: podman-forgejo-db.service: Failed with result 'exit-code'. Consumed 1.047s CPU time over 5min 37.657s wall clock
2026-09-27T10:13:55-04:00 melon systemd[1]: forgejo.service: Job forgejo.service/start failed with result 'dependency'.
2026-09-27T10:13:55-04:00 melon systemd[1]: Dependency failed for Forgejo (Beyond coding. We forge.).
2026-09-27T10:14:17-04:00 melon systemd[1]: Started podman-forgejo-db.service. (restart counter 1)
```

The identical triplet fired on 09-25 19:32:31. Those two forgejo lines are the **only** `forgejo.service` journal lines in either boot: the app never launched (zero application log lines, `NRestarts=0`, `Result=success`, start-limit never involved).

### 4.2 The DB container's first-boot failure

```
conmon[…] Failed to write 137 to container exit file: Failed to create file "/run/libpod/persist/f2b9600c…/exit.I234V3": No such file or directory
podman: Error: saving container … state: beginning container … save transaction: database is locked
systemd: podman-forgejo-db.service: Main process exited, code=exited, status=126/n/a
```

Boot contention context: 11 container creates in the first 12 min; 878 `database is locked` errors across containers this boot (Lidarr 488, Sonarr 169, grafana-start 128, navidrome 58, Radarr 26, Prowlarr 6, podman-forgejo-db 1, …). Baseline: **0** podman start failures in the 12 h before the reboot — this is a boot-time storm, not chronic flakiness.

### 4.3 The 39.5 h metric trail

- `traefik_service_server_up{service="git@file"}` = 0 continuously from 2026-09-25T23:32Z (last 1 at 23:11Z, reboot gap 23:12–23:31Z) until the 11:05 recovery — independently verified by range query
- `namedprocess_namegroup_num_procs{groupname="forgejo"}`: 1 continuously since 09-20, gone after the 09-25 reboot (empty-group sentinel) — the process never returned

### 4.4 The re-stamped alert (and two artifacts it spawned)

`activeAt 10:18 EDT, for=3m` implied a fresh failure; the underlying series had been 0 for 38.5 h. Grafana-managed rule state resets when Grafana restarts — which the reboot caused. The apparent gotify "blip" at 10:15 and lidarr "unhealthy" at 10:44 were the same family of artifacts: gotify's `changes(...[24h])` = **0** (never down — no blip exists) and lidarr's = **5354** (permanent flapping, baseline noise). The alert itself had been firing since 09-25 ~19:35.

## 5. Ruled out

| Hypothesis | Killing evidence |
|---|---|
| Disk full | `node_filesystem_avail_bytes` flat: 132.6 GB free on `/`, 10.63 TB on `/mnt/media`; no forgejo/container mount exists |
| OOM / memory exhaustion | `node_vmstat_oom_kill` = 0 (7 d); 28 GB available post-boot; swap untouched; no OOM text in journal |
| Unclean crash / power event | logind D-Bus reboot ("The system will reboot now!"), ordered stops, `Reached target System Reboot`; three hosts staggered 17/10 min apart |
| A `nixos-rebuild switch` | No new generation at boot (12-day-old closure re-entered); no activation/rebuild journal lines; newest generation on disk is 09-19 |
| Forgejo app crash | It never started — zero app lines in both boots; last app activity was the clean 09-25 19:11:30 SIGTERM |
| Start-limit burn (issue-08 mode) | `NRestarts=0`, `Result=success`; the psql wait-loop + `TimeoutStartSec=600` are deployed and worked as designed |
| LAN-wide outage | Only `git@file` was 0; every other `@file` backend healthy |
| gotify blip ~10:15 EDT | No such blip: `changes(...[24h])` = 0 — alert-path artifact across Grafana restart |
| lidarr unhealthy ~10:44 EDT causal | Baseline flapping (5,354 changes/24 h); its flap window started 09:00, unrelated to forgejo |
| 10:15/10:18 EDT onset | Artifact: `activeAt` re-stamp after Grafana restart (§4.4) |

## 6. Root cause

A clean reboot triggers podman's all-containers-at-once start storm. Boot-time boltdb/SQLite lock contention (see §4.2; lidarr's spin is the leading contender — `docs/issues/11-lidarr-cpu-spin.md`) makes the `forgejo-db` container's first start fail (exit 126). Because `forgejo.service` declares `Requires=podman-forgejo-db.service` (`generic/server/forgejo.nix`), the DB unit's failure cancels forgejo's start job, and systemd never re-queues a dependency-failed job — so forgejo remains down indefinitely even after the DB recovers. Confidence high: every link is a verbatim journal line; the podman-internal trigger (exit 126 cause) is inferred from the conmon/boltdb error strings.

## 7. Fix and follow-ups

1. **`upholds=` (implemented, uncommitted, deploy pending)** — `generic/server/forgejo.nix` now sets `upholds = [ "${backend}-forgejo-db.service" ]` beside `requires`. When the DB unit comes up via its own `Restart=`, systemd re-queues forgejo's start job; `requires` still propagates failures. `docs/issues/10-forgejo-dependency-fail-after-reboot.md`.
2. **melon runner** — pending at time of writing: `sudo systemctl reset-failed gitea-runner-melon.service && sudo systemctl start gitea-runner-melon.service` (crash-loop burned the start-limit; onion's self-heals).
3. **Alert blind spot** — add a companion rule `max_over_time(traefik_service_server_up{service=~".*@file"}[1h]) == 0` so a multi-hour backend outage is distinguishable from a reboot-reset blip at a glance.
4. **Postgres unclean shutdown every boot** — podman removes the DB container mid-write during the boot storm; postgres performed crash recovery both boots. Recurring data-integrity risk worth its own investigation.
5. **Booting the intended generation** — melon booted a closure built from the 09-15 nixpkgs while the newest generation on disk is 09-19 (system-368). Several repo fixes postdate the booted closure; confirm the next boot picks up the newest generation.
6. **Debug decoders learned** — added to `docs/debug.md`: forgejo's unit-lifecycle lines live in `init.scope` (no `unit` label); `!= "caller="` dodges Loki self-echoes in `count_over_time`; Grafana-restart re-stamps `activeAt`.

## References

- `docs/issues/10-forgejo-dependency-fail-after-reboot.md`, `docs/issues/11-lidarr-cpu-spin.md`
- `docs/issues/done/08-forgejo-db-start-race.md` (same symptom class, prior mechanism)
- `docs/debug.md` §Forgejo specifics, §Known noise, §Prometheus playbook
- Evidence: Loki `{service_name="systemd-journal"} |= "forgejo.service"` and `|~ "Failed to start podman-"` over both boots; Prometheus `traefik_service_server_up{service="git@file"}` (3 d range), `namedprocess_namegroup_num_procs{groupname="forgejo"}` (7 d), `node_boot_time_seconds` (7 d), `node_vmstat_oom_kill`, `node_filesystem_avail_bytes`
