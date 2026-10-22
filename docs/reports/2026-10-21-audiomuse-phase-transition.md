# AudioMuse Phase Transition — Simultaneous CPU Step-Down on melon and onion — 2026-10-21

- **Systems affected:** audiomuse workers on melon (worker-1/2) and onion (worker-1) — all three changed workload regime at once; collateral: Navidrome/Immich/Transmission bounced by the melon switch (~100 s of 502s), Transmission stop-phase timeout
- **Impact:** sustained step-down in CPU/load on both hosts (melon 31.5 → 10.9 busy cores of 64, load1 35 → 15; onion 6.9 → 3.4 of 16, load1 7.1 → 3.7); ~106 Navidrome albums skipped without analysis (regenerable); no service break, no data loss
- **Onset:** 2026-10-21 18:30:26 EDT (melon switch); phase transition logged 18:31:01 EDT
- **Recovery:** none needed — all units healthy, analysis progressing faster than before (~2.1 albums/min vs 0.5)
- **Status:** resolved; no config fix required
- **Methodology:** four parallel lanes (journal/Loki timeline, Prometheus resources, repo/config review, live SSH state) + coordinator verification of the two decisive claims (phase-transition log line, CPU step). All times EDT (UTC−4).

## 1. Executive summary

"Resource usage changed on both melon and onion at 18:30" — a user-observed step-down in CPU/load on both hosts at the same instant. Two things happened nearly simultaneously, and only one is causal:

1. **The flake-update deploy (the trigger, not the cause):** the daily flake bump committed at 18:21:32 (nixpkgs `20261018.8ce7336` → `20261020.cd4ea8d`), onion switched at 18:27:11, melon at 18:30:26. Melon's activation stopped Navidrome/Immich/Transmission for ~100 s (18:30:30–18:32:11). No audiomuse unit restarted — all five units (`postgres`, `flask`, `worker-1/2` on melon, `worker-1` on onion) kept their Oct 19 `ActiveEnterTimestamp`s, `NRestarts=0`, same container IDs and PIDs.
2. **The server-pass change (the cause):** at 18:31:01 the shared `MainAnalysisTask` logged `Union analysis phase 2/2: Jellyfin` — the app's own status wording (logs/UI) for moving to the next media server in its documented sequential pass. Upstream `docs/MULTI_SERVER.md` (which never uses "phase" terminology): "Analysis processes every configured server sequentially, with the default server first", "run one server at a time, in sequence". On the Navidrome pass every unmapped track is downloaded and run through MusiCNN/CLAP/Whisper (CPU-heavy); on the Jellyfin pass most tracks resolve against the shared catalog as duplicates and "just gain a `track_server_map` row" instead of repeating the pipeline (`already catalogued … running only its missing stages (nothing)`). All three workers share the one postgres queue, so the regime change was instantaneous and identical on both hosts — CPU-heavy inference → cheap duplicate mapping.

The switch set the **timing**: while Navidrome was down, the workers' Navidrome calls 502'd and the remaining ~106 Navidrome-pass albums were skipped in ~15 s (`Skipping album … no tracks returned` ×81, `Source audio unavailable` ×28), closing out the Navidrome pass at 18:30:45 (counter 1754 → 1860) and starting the Jellyfin pass at 18:31:01 — roughly 3–4 h earlier than Navidrome-pass pace would have reached it. The skipped albums were never analyzed (verified 2026-10-21: sampled skip-line titles — *Surtur Rising*, *Fate of Norns*, *Black Ice*, *Who Made Who*, *American Recordings* — have zero occurrences in any worker log over the 45 h before 18:30). The UI showing the analysis "moved on" is consistent — the counter jumped past them via silent INFO-level skips.

## 2. Timeline

All times EDT (UTC−4), 2026-10-21. Sources: Loki (journald), Prometheus, live unit state, git reflog.

| Time | Event | Source |
|------|-------|--------|
| 18:21:32 | `flake: update inputs` commit (nixpkgs bump only); CI `test.yml` fires on both hosts (they run their own runners) | git log |
| 18:20:13–18:24:18 | Grafana SQLITE_BUSY flap, `/-/ready` 500s — **pre-dates the switches**, separate pre-existing issue | Loki |
| 18:26:25 | onion pulls master | reflog |
| 18:27:11 | onion `nixos-rebuild switch` (generation 522); does not touch the audiomuse worker | journal |
| 18:30:26 | **melon switch** (generation 381, same nixpkgs closure) | journal |
| 18:30:30–18:32:11 | melon activation stops/starts Navidrome, Immich, Transmission; Navidrome down in between | journal |
| 18:30:32–48 | Worker Navidrome 502s: 110 lines on onion, 23 on melon; 106 phase-1 albums skipped | Loki |
| 18:30:45 | `MainAnalysisTask` album counter jumps 1754 → 1860 | Loki |
| 18:31:01 | `Union analysis phase 2/2: Jellyfin` (onion worker-1, the orchestrating worker) | Loki |
| 18:31–18:35 | CPU step-down completes on both hosts; sustained through end of investigation (19:44) | Prometheus |
| 18:32:00 | `transmission.service: Failed with result 'timeout'` (stop phase); restarted, recovered | journal |
| 19:44 | Live: `Albums 2004/3709`, melon workers analyzing albums, forked python children ~300% CPU each (new regime's occasional real analyses) | SSH |

## 3. Root cause and fixes

| # | Root cause | Fix | Where |
|---|-----------|-----|-------|
| 1 | The union analysis moves between media servers in its documented sequential pass (upstream `docs/MULTI_SERVER.md`: default server first, one at a time; the "phase N/2" wording is the app's log/UI status, not upstream terminology). On the Jellyfin pass duplicate tracks resolve against the shared catalog (embedding signature + duration + Chromaprint) and gain a `track_server_map` row instead of re-running MusiCNN, so worker CPU collapses while throughput rises | None needed | upstream `docs/MULTI_SERVER.md` |
| 2 | melon switch stopped Navidrome mid-pass; worker 502s skipped the remaining ~106 Navidrome albums (never analyzed — zero prior log occurrences, verified), advancing the pass change by ~3–4 h | Re-run Navidrome analysis (next full run or re-trigger in UI) to cover albums ≈1755–1860 | user follow-up |

**Decisive verification (coordinator pass):**

- LogQL `{unit=~"podman-audiomuse-worker-.*"} |~ "Union analysis phase"` (22:00–23:35 UTC) → exactly one line: phase 2/2 at `1792621861060733000` (22:31:01.060733 UTC) from onion's `podman-audiomuse-worker-1`, container `4e798aec219f`.
- PromQL `sum by (instance, mode) (rate(node_cpu_seconds_total{instance=~"localhost:.*|onion.lc.brotherwolf.ca:.*",mode=~"user|system"}[5m]))` range 22:00–23:35 step 300 → flat-high to the 22:30 sample, step to the new regime by 22:35, flat-low through 23:35 on both hosts.

**Ruled out:** audiomuse unit/container restart or `Upholds` bounce (Oct 19 timestamps, `NRestarts=0`, stable IDs); postgres/mTLS breakage (zero SSL/pg_hba/connection errors); job finished or stalled (task `d4deb264…` continuous, counter advancing); any 18:30 timer on either host (the 18:00+45 min auto-upgrade is unimported dead config since 2025-09-01); CI/runner load (both runners inactive in the window); worker-count regression (2 on melon, 1 on onion, unchanged since the 10-17 oversubscription fix).

## 4. Follow-ups

- Re-analyse the skipped Navidrome albums (≈1755–1860 of 3709) once phase 2 completes — expected ~09:15 EDT 2026-10-22 at ~2.1 albums/min (~1,849 Jellyfin albums), with brief CPU bumps if any Jellyfin albums are non-duplicates.
- Grafana flap (SQLITE_BUSY from 18:20, predates everything): if still flapping, `sudo systemctl restart grafana` on melon; MCP went 503 mid-investigation and lanes fell back to direct Prometheus/Loki APIs. Consider filing as a separate issue if it recurs.
- Add an audiomuse namegroup to process-exporter (`generic/prometheus.nix`) — today's per-worker CPU had to be inferred from host arithmetic plus log counters.
- Optional, only if in-container worker restarts (18:50/18:56/19:33, unsynchronized supervisord default-queue restarts, no journal traceback) recur: sudo script to read supervisord's logs inside the containers.
- `docs/debug/audiomuse.md` gained a decoder for the phase-transition CPU step; no topic-table change needed.
