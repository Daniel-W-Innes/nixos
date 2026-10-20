# AudioMuse mTLS Deploy — Stack Bounce + Worker Probe Hang — 2026-10-19

- **Systems affected:** audiomuse stack on melon (postgres/flask/worker-1/worker-2), the new onion remote worker, and the running `MainAnalysisTask`
- **Impact:** ~2.5 min stack bounce on melon (21:35:48–21:38:14 EDT, UI 502s, in-flight album tasks SIGTERMed); the analysis task requeued itself and resumed, **no data loss**; onion's worker activation hung for ~14 min before the fix (21:17–21:31, user-cancelled); collateral: onion's root filesystem hit 100% from the day's image pulls
- **Onset:** 2026-10-19 21:17 EDT (first onion test activation wedging on the unbounded probe)
- **Recovery:** self-healed 21:37:53–21:38:14 EDT once melon's postgres came up with `ssl=on`; probe bounded by a config fix (`PGCONNECT_TIMEOUT`)
- **Status:** resolved; fixes uncommitted in the working tree (per repo convention)
- **Methodology:** two parallel lanes (Loki/journal timeline, live SSH state on melon) + one independent verification pass. All times EDT (UTC−4).

## 1. Executive summary

The 2026-10-19 deploy added a remote audiomuse worker on onion with mTLS on the postgres path. Two independent problems surfaced, plus one expected bounce:

1. **The bounce (expected):** switching melon restarts the postgres container, and because the app units declare `Upholds=podman-audiomuse-postgres.service`, that restart cascades to flask and the workers by design. The stack was down ~2.5 min; the `MainAnalysisTask` (at Albums 552/3688) was SIGTERMed mid-track, requeued itself, and resumed with its album counter reset (already-analyzed tracks are skipped, so no meaningful re-work). The UI returned to 200 at 21:38:14.
2. **The probe hang (config bug, fixed):** onion's worker `ExecStartPre` is a full mTLS psql login. Run before melon was switched, it dialed `melon:5433` where nothing listened — but melon's firewall **drops** the SYN (5433 is not an allowed input port; the publish only works via netavark DNAT after the switch), so each psql attempt hung for the full TCP timeout. With 90 iterations and no `PGCONNECT_TIMEOUT`, the unit wedged in `start-pre` for hours and `switch-to-configuration` appeared hung. Fixed: `PGCONNECT_TIMEOUT=5` + 30 iterations → worst case ~3 min, then `Restart=on-failure` retries until melon is up.
3. **Collateral — onion root fs full (recovered):** the day's container image pulls (rootful audiomuse worker + rootless storage) plus accumulated user data filled the 96G root. Trash + rootless `podman system prune -a` reclaimed ~36G (root back to 89%); journal vacuum + rootful prune offered as follow-up.

No mTLS defects were found: postgres started with `ssl=on` and the custom pg_hba cleanly (zero cert/permission/hba errors), melon-side waits passed, and the onion worker's probe succeeded on its third retry and began pulling analysis jobs over the verified TLS connection.

## 2. Timeline

All times EDT (UTC−4), 2026-10-19. Sources: Loki (journald), live SSH state, unit states.

| Time | Event | Source |
|------|-------|--------|
| 21:17:13 | Onion test activation starts `podman-audiomuse-worker-1`; probe wedges in `start-pre` (melon firewall DROPs 5433; no connect timeout) | systemd, ps |
| 21:26 | Second onion test activation, blocked on the same unit; diagnosis: melon still loopback-published, probe unbounded | session |
| 21:30:50–52 | User cancels activation, stops worker unit (clean) | systemd |
| 21:33:52 | Onion probe timeout #1 (melon not switched) | journal |
| 21:35:48 | melon switch: postgres restart → Upholds cascade stops flask/worker-1/worker-2 | systemd |
| 21:36:04 | Workers SIGTERMed mid-album (`MainAnalysisTask` at Albums 552/3688) | journal |
| 21:36:27–58 | Postgres stops cleanly; unit restarts; `installPgSsl` succeeds; new container with `-c ssl=on` + custom hba | journal |
| 21:37:04–07 | PostgreSQL ready to accept connections (4 benign "starting up" FATALs from racing probes) | journal |
| 21:37:14–19 | Flask + both workers up; their pg_isready waits pass against the new hba | systemd |
| 21:37:53 | Onion probe succeeds (3rd attempt); worker joins the queue | journal |
| 21:38:03 | Onion worker resumes `MainAnalysisTask` over mTLS (attempt 4/4 — last allowed) | journal |
| 21:38:14 | UI healthy; `/api/health` 200 direct and via traefik | curl |
| 21:44:52 | Analysis progressing (Albums 3/3709; counter reset, analyzed tracks skipped) | journal |
| ~21:50 | Onion root fs 100% full → docs write fails ENOSPC; trash + rootless prune reclaim ~36G | session |

## 3. Root causes and fixes

| # | Root cause | Fix | Where |
|---|-----------|-----|-------|
| 1 | `Upholds=` intentionally ties app units to postgres lifecycle → any postgres restart bounces the stack | None needed (by design); the byte-identical `waitForPostgres` binding keeps melon switches that don't touch postgres from restarting the app units at all | `generic/server/audiomuse.nix` |
| 2 | Probe assumed fast failures; firewall DROP + no connect timeout = hours of `start-pre` | `PGCONNECT_TIMEOUT=5`, 30 iterations (~3 min bound) | `generic/server/audiomuse.nix` |
| 3 | Onion root fs capacity | Vacuum journal (2.3G), prune rootful podman (sudo), keep an eye on rootless storage — **done 2026-10-19** (journal vacuumed, rootful podman pruned +5.4G; root at 81%, 19G free) | user follow-up |

## 4. Follow-ups

- `docs/debug/audiomuse.md` gained two decoders: the switch-time bounce (Upholds cascade) and the probe-hang symptom map; `docs/debug.md` topic table updated.
- Watch `MainAnalysisTask` (attempt 4/4) and one album task (2/2): no action unless they fail — re-trigger in the UI if so.
- Consider: root disk usage on onion (Steam/PrismLauncher/nerd-dictation in `/home`), and a `pg_dump` timer for `/var/lib/audiomuse/postgres` (still no backups).
