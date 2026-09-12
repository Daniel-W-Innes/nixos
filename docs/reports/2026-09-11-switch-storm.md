# Switch-Storm Outage Post-Incident Report — melon, 2026-09-11

- **Systems affected:** forgejo (+ `forgejo-db` podman postgres), gitea-runner-melon / gitea-runner-onion (CI), transmission; transient stop-phase failures in prowlarr/sonarr/radarr/jellyfin/dawarich-web/immich-machine-learning and five podman containers
- **Impact:** `git.lc.brotherwolf.ca` down ~13 min; CI runners down ~16 min; transmission down ~28 min (torrent traffic + arr download client); ~1-min blips for the stop-phase cluster; **no data loss** (postgres shut down cleanly, restarted from the existing data dir)
- **Onset:** 20:51 EDT (switch stop phase)
- **Recovery:** forgejo 21:09:22 EDT, transmission by 21:23:19 EDT (manual `systemctl start`s); runners recovered with forgejo
- **Status:** resolved; config fix implemented (`generic/server/forgejo.nix`, deploy pending) — `docs/issues/done/08-forgejo-db-start-race.md`
- **Methodology:** Loki + Prometheus via mcp-grafana MCP, plus repo inspection; no SSH. Each claim's source is noted. All times EDT (UTC−4).

## 1. Executive summary

A `nixos-rebuild switch` after the daily flake update (nixpkgs bump, forgejo 16.0.3) restarted nearly every service on melon. The switch finished with three units failed:

1. **forgejo** lost a start race against its own database: the switch recreated the `forgejo-db` postgres container (~5 min), and the module's preStart `forgejo migrate` fails fast when the DB socket is absent — forgejo burned its start-limit retries (4 attempts in ~2 s) and stayed failed even after postgres came up 35 s later. Our psql wait-loop existed but ran *after* the module's migrate in the merged preStart, so it never got a chance.
2. **gitea-runner-melon** was a pure cascade: with forgejo down, traefik returned 503 to the runner's `Declare` call and it crash-looped (exit-code every ~2.5 s) until manually restarted after forgejo recovered. onion's runner also 503'd but stays alive retrying and self-healed.
3. **transmission** wedged twice: the old daemon (6 d 5 h uptime) wedged on stop during the switch (SIGTERM timeout → SIGKILL), and its replacement timed out *starting* while the proton VPN namespace was still settling, then wedged on SIGTERM again (SIGKILL at 21:01:03). It needed only a manual start once the namespace was up.

Recovery was three `systemctl start`s. The permanent fix for the forgejo race — `mkBefore` psql wait + `mkAfter` admin-create + `TimeoutStartSec=600` — is implemented and verified but not yet deployed.

## 2. Timeline

All times EDT (UTC−4), 2026-09-11. Sources: Loki (journald) on melon.

| Time | Event | Source |
|------|-------|--------|
| 20:05 | Slow forgejo SQL begins (8–10 s `action_runner`/`access_token` updates, 3–4 s `FetchTask`) — 45 min before the switch, unresolved (see §7.1) | forgejo.service |
| 20:51:11 | Switch stop phase: old forgejo (PID 416616) SIGTERM → clean shutdown | forgejo.service |
| 20:51:40–47 | Old `forgejo-db` postgres container fast shutdown, clean ("database system is shut down") | podman-forgejo-db.service |
| 20:52:41 | **Stop-phase timeout cluster**: transmission, prowlarr, sonarr, radarr, jellyfin, dawarich-web, immich-ml all fail "with result 'timeout'" at the same second (stop order + 90 s TimeoutStopSec) → SIGKILL; all recover except transmission. Several podman containers fail 'exit-code' around the same window | systemd |
| 20:53:47 | proton namespace up ("Waiting for wireguard endpoint '66.234.146.98'... success!"); new transmission pre-start begins; **first gitea-runner-melon failure** — crash loop starts | proton.service, transmission.service, gitea-runner-melon.service |
| 20:53:41–20:56:06 | `forgejo-db` container recreated (image pull → create → start, ~2.5 min in podman) | podman-forgejo-db.service |
| 20:56:13–15 | New forgejo (16.0.3) preStart `forgejo migrate` fails 4×: `dial unix /run/forgejo-db/.s.PGSQL.5432: connect: no such file or directory`; start-limit hit → **failed** | forgejo.service |
| 20:56:50 | Postgres "database system is ready to accept connections" — 35 s after forgejo gave up | podman-forgejo-db.service |
| 20:56:50 | Transmission replacement: "start operation timed out" (never signaled ready) | systemd |
| 21:01:03 | Transmission: stop-sigterm timeout → SIGKILL → failed 'timeout' | systemd |
| 21:02:21 | Uptime-kuma monitors #5 'Transmission' and #30 'Arr' go Failing (502s / 48-s timeouts) | uptime-kuma.service |
| 21:06–21:08 | Runner still crash-looping (`fail to invoke Declare: 503`); onion's runner 503ing but alive (`failed to fetch task`) | gitea-runner-*.service |
| 21:09:22 | **Forgejo recovered** — manual start, migration clean, service up | forgejo.service |
| 21:11:44 | Last kuma 'Transmission' Failing line; monitor lines for #5/#30 then stop (see §7.3) | uptime-kuma.service |
| 21:23:19 | Transmission daemon (PID 3598607) active — tracker announces flowing through the VPN | transmission.service |
| 21:42–21:45 | Verified healthy: forgejo serving 200s, runner polling `/api/v1/version` in 52.6 ms | forgejo.service |

## 3. Scope of impact

**Broken (all recovered):**

- forgejo + `git.lc.brotherwolf.ca` — 13 min (20:56:15 → 21:09:22), including all CI: both runners down/erroring, PR checks blocked
- transmission — ~28 min (20:52:41 → by 21:23:19): torrent traffic halted, arr download client unavailable, kuma monitors #5 and #30 Failing
- Transient (~1 min each): prowlarr, sonarr, radarr, jellyfin, dawarich-web, immich-machine-learning (stop-phase SIGKILLs, restarted cleanly), five podman containers ('exit-code', recovered), Lidarr monitor #17 (500s at 21:04:25 during the storm)

**Unaffected:**

- Data: postgres shut down cleanly and restarted from the existing data dir ("Skipping initialization"); forgejo's 16.0.3 migration ran unchanged and clean on the manual start
- The observability stack itself: Loki/Prometheus kept the journal stream intact throughout — this entire report was written from it
- The proton VPN: endpoint reachable throughout (proton-up success at 20:53:47)
- onion's runner process: stayed alive through the outage (retrying), self-healed

## 4. Key evidence

### 4.1 Forgejo's start race (the root cause)

Four fatal attempts in ~2 s, each a full unit activation (fresh PID, `environment-to-ini` re-run), all with the same error — the socket simply didn't exist yet:

```
forgejo-pre-start: [F] Failed to initialize ORM engine: failed to connect to
`user=forgejo database=forgejo`: /run/forgejo-db/.s.PGSQL.5432
(/run/forgejo-db): dial error: dial unix /run/forgejo-db/.s.PGSQL.5432:
connect: no such file or directory
```

Postgres declared itself ready at 20:56:50 — 35 s after the last attempt. The unit never retried: `Restart=always` + 4 rapid failures exhausted the start-limit (5 starts / 10 s).

### 4.2 The DB container's ~5 min recreation

Old container: fast shutdown at 20:51:40, removed 20:52:39. New one: image pull 20:53:41, container create 20:55:06, start 20:56:06, socket listening 20:56:31, accepting connections 20:56:50. podman was concurrently recreating every other container, which explains the pace. "Container started" ≠ DB ready — the exact gap the fix addresses.

### 4.3 Runner cascade — 503 through a healthy traefik

`gitea-runner-melon` (new PID every ~2.5 s): `fail to invoke Declare: unavailable: 503 Service Unavailable`. The 503 is traefik's backend-down response — traefik itself was up and routing the whole time, which is why the runners kept getting answers instead of connection errors.

### 4.4 Transmission's two wedges

- Old daemon (PID 901014, up 6 d 5 h): `State 'stop-sigterm' timed out. Killing.` → SIGKILL → "Failed with result 'timeout'" at 20:52:41 — the known single-threaded wedge, this time manifesting on *stop*.
- Replacement (PID 3571791, up 3 min 2 s): "start operation timed out. Terminating." at 20:56:50, then wedged on SIGTERM → SIGKILL at 21:01:03 — it had started while the proton namespace plumbing was still settling (proton-up logged success at 20:53:47; the confined start followed).

### 4.5 The stop-phase timeout cluster

Seven unrelated units failed with 'timeout' at *exactly* 20:52:41 — stop order issued at ~20:51:11 + the default 90 s `TimeoutStopSec`. This same-second cluster is the normal signature of a full-flake-update switch stopping wedged-or-slow units, not a shared dependency failure (the units share nothing but the switch itself).

## 5. What was ruled out

| Hypothesis | Evidence against |
|---|---|
| Forgejo 16.0.3 upgrade/migration incompatibility | The failure was a socket connect, not a schema error; the identical migration ran clean at 21:09:22 against the same DB |
| Postgres data loss/corruption | Clean fast shutdown at 20:51:47; "Skipping initialization" on restart; normal checkpoints after |
| Traefik misconfiguration | Runners received proper 503 backend-down responses — traefik up and routing throughout |
| proton tunnel outage | Endpoint reachable at 20:53:47 ("success!"); transmission's failure was start/stop ordering, not a dead tunnel |
| Observability stack outage | Grafana 503'd briefly while restarting in the switch; Loki/Prometheus never lost the stream (this report is the proof) |
| The 20:05–20:51 slow-SQL window | Predates the switch by 45 min; unrelated to the three failures (unresolved, §7.1) |

## 6. Root-cause analysis

**Cause 1 — forgejo: DB start race, made fatal by preStart ordering.**
The switch legitimately recreated the `forgejo-db` container (flake update → container definitions changed → image re-pulled). forgejo's start depends on the DB socket, but the nixpkgs module's preStart runs `forgejo migrate` *before* our psql wait-loop (preStart is `types.lines` — definitions concatenate in priority order, and both were priority-default). Migrate fails fast on a missing socket; `Restart=always` re-runs it ~4× in 2 s; the start-limit lands the unit in a permanent failed state. The fix reorders the merged preStart (`mkBefore` wait, `mkAfter` admin-create) and raises `TimeoutStartSec` to 600 so the wait can outlast a DB recreation; `Restart=always` then covers anything longer.

**Cause 2 — runner: pure cascade.** No independent fault: `Declare` → 503 → exit → restart loop, its own start-limit eventually landing it in failed. Behavior difference worth remembering: melon's runner crash-loops into a failed state and needs a manual start; onion's runner retries without exiting and self-heals.

**Cause 3 — transmission: stop-wedge + start-during-namespace-settling.** The old daemon wedged on stop (directly observed; the single-threaded model makes both directions block). The replacement's start timeout is *medium confidence*: the daemon logs nothing (message-level 3), so the missing ready-signal mechanism isn't directly observed — the namespace-settling timing is the best-supported explanation, consistent with the 2026-09-03 wedge model. A confirm would be a manual `systemctl start transmission` right after a namespace rebuild with `journalctl -u transmission` open.

**Contributing factor:** the flake update itself. A nixpkgs bump changes nearly every package, so the switch restarts nearly every service — the storm is expected behavior; the failures are what the fix targets.

## 7. Adjacent findings (not causal, worth attention)

1. **45 min of slow forgejo SQL before the switch** (20:05–20:51: 8–10 s `UPDATE action_runner SET last_online`, 8–10 s `access_token` updates, 3–4 s `FetchTask` responses). DB/disk contention on the old container, unexplained and not chased (baseline-first rule). Worth a look only if it recurs.
2. **Sluggish postgres checkpoints during the window** — the 20:51:46 shutdown checkpoint logged `sync=2.152 s, longest=1.145 s` (vs `sync=0.5 s` after restart). Consistent with the switch's I/O storm; not causal.
3. **Kuma monitor silence after 21:11:44** — monitors #5 'Transmission' and #30 'Arr' logged Failing every 60 s from 21:02 to 21:11:44, then nothing, with no "Up" line, although the daemon was verified active at 21:23:19. Uninvestigated (kuma logs, monitor state, or an uptime-kuma restart would explain it).
4. **Container-recreation trigger not pinned down** — the switch recreated the DB container and re-pulled `postgres:16-alpine`, but the exact trigger (oci-containers definition hash vs. podman image-store state) was not determined.

## 8. Recommendations

1. **Deploy the forgejo fix** (next `nixos-rebuild switch` on melon) and re-exercise it once: switch while the `forgejo-db` container is down — forgejo should wait and come up on its own.
2. **Check for the same pattern elsewhere**: any service whose preStart does DB work against a podman container socket (bookorbit, dawarich, searx/redis, meilisearch) deserves the same wait-first ordering.
3. **Transmission watchdog** (`docs/issues/06-transmission-watchdog.md`) gains urgency: the stop-wedge shows that even recovery-by-restart needs two attempts (kill the wedge, then start after the namespace settles) — a watchdog with the right ordering would make this one command.
4. **After every flake-update switch, act on the failure warning**: the units listed are the ones still failed, not noise — each is either a real casualty (this incident) or needs a manual start (transmission).
5. **Chase the slow-SQL window and the kuma silence** only if they recur (baseline first).

## Appendix — sources & methods

- **Loki** (UID `P8E80F9AEF21F6940`, melon journal stream): `{unit="forgejo.service"}`, `{unit="podman-forgejo-db.service"}`, `{unit="gitea-runner-*.service"}`, `{unit="transmission.service"}`, `{unit="proton.service"}`, and text-filtered systemd messages (`{service_name="systemd-journal"} |= ".service: Failed with result"`, `|= "MONITOR"`) over 2026-09-12T00:00–01:47Z
- **Repo**: `generic/server/forgejo.nix` (+ fix diff), `generic/forgejoRunner.nix`, `generic/server/arr.nix`, pinned nixpkgs `forgejo.nix` module
- All UTC timestamps converted to EDT (UTC−4); journal MESSAGE fields already carry EDT

Follow-up: `docs/issues/done/08-forgejo-db-start-race.md`; playbook updates in `docs/debug.md` (§Forgejo specifics, §Transmission specifics, §Switch storms, §Journal data).
