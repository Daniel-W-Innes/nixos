# Forgejo outage — tmpfiles chowns the live postgres data dir to the wrong uid

**Open.** Opened 2026-10-16. Recovery applied 2026-10-16 21:27 EDT; repo fix in working tree (`generic/server/forgejo.nix`), deploy pending.

### Problem

`systemd.tmpfiles.rules` for the forgejo-db data dir used `999 999` (`d /var/lib/forgejo/postgres 0700 999 999 -` + `Z ... 999 999`), but `postgres:16-alpine` runs postgres as **uid/gid 70** (999 is the Debian image's uid). Rootful podman, no userns/uidmap anywhere — container uid == host uid. The postmaster runs with `CapEff: 0`, so DAC applies strictly.

On every `nixos-rebuild switch` the activation re-runs `systemd-tmpfiles --create --remove` (via `systemd-tmpfiles-resetup.service`), which re-applies **all** rules. systemd 260.5's `create_directory()` applies owner/mode to *existing* dirs too (`CREATION_EXISTING`), so the `d` rule chowned the live data-dir root to 999:999. Uid 70 then lost traverse permission on the mount root: the postmaster kept running on its open fds (last healthy checkpoint 20:52:30), but every new connection FATALed on the first file it opens — `global/pg_filenode.map` — first FATAL 20:53:13, one per preStart probe (1/s). The `Z` recursive rule never runs: systemd refuses it with `Detected unsafe path transition /var/lib/forgejo (owned by forgejo) → /var/lib/forgejo/postgres (owned by …)` because the parent and target owners differ — it has been dead code since `fa3a38d` (2026-08-02); the warning independently confirms the `d` rule as the chowner (it names the child `nm-iodine` only after `d` chowned it in the same run).

Why it took 3 months to surface: the bug **fired on 2026-10-08 too** — the identical tmpfiles warning pair (`uptime-kuma` + `forgejo` unsafe path transition) is in the journal at 21:39:59 EDT, during the switch that bumped podman 5.8.7→5.8.8. That switch also recreated the DB container, and the image entrypoint re-chowns PGDATA on container start, masking the damage (postgres back up at 21:41:57, forgejo Started 21:43:27). The 2026-10-16 switch (nixpkgs 20261015) bumped forgejo 16.0.5→16.0.6 — restarting `forgejo.service` and touching `/etc/tmpfiles.d` (the nixpkgs forgejo module embeds the package out-path in a rule) — but **not** the postgres image, so nothing repaired the chown. Forgejo's preStart psql wait loop then spun until `TimeoutStartSec=600` (`Failed with result 'timeout'`, exactly three cycles: 21:03:11.856, 21:13:12.357, 21:23:12.857 EDT), repeating via `Restart=always`. uptime-kuma logged `Forgejo Server` Pending (503) from 20:52:32, Failing every 60 s from 20:55:35 through 21:27:32 — never reaching the all-caps DOWN state.

### Fix

- **Recovery (applied):** `chown -R 70:70 /var/lib/forgejo/postgres` (numeric ids — host uid 70 collides with the `transmission` user). The running preStart probe succeeded within seconds; forgejo was `active (running)` by 21:27:47 EDT. **Do not restart `podman-forgejo-db` before fixing ownership** — postgres refuses to start on a wrong-ownership dir and the container would restart-loop.
- **Repo (working tree):** `generic/server/forgejo.nix` tmpfiles rules corrected `999 999` → `70 70`, with a comment. The `Z` line is dead code (unsafe-path-transition refusal) and could be dropped; the `d` rule now matches the image so re-runs are no-ops.
- **Longer term:** `image = "postgres:16-alpine"` is tag-only with `podman.autoPrune` on, so the image content (and its postgres uid) can drift on re-pull — consider digest-pinning and/or setting `user = "70:70"` on the container so the intent is explicit.

### Verification

- `stat /var/lib/forgejo/postgres` = `700 70:70`; `pg_filenode.map` = `600 70:70`; histogram all `70:70` (2296 entries).
- Recovery was out-of-band (the manual chown only — no switch, no DB-unit lifecycle, no postgres start/shutdown in the recovery window): last `pg_filenode.map` FATAL 21:27:27.479, preStart psql succeeded 21:27:34.354, systemd `Started Forgejo` 21:27:47.575, uptime-kuma/gotify `[Forgejo Server] [Up]` 21:28:33.555 EDT.
- `forgejo.service` `active (running)` since 2026-10-16 21:27:47 EDT; `ExecStartPre` exit 0/SUCCESS.
- `traefik_service_server_up{service="git@file"}` = 1 after recovery.
- Pending: next switch must not re-break it (tmpfiles re-run should now be a no-op — verify with `find /var/lib/forgejo/postgres \( ! -uid 70 -o ! -gid 70 \)` = empty afterwards); next DB container recreation should start cleanly. The CHASE_SAFE warning may persist after deploy (parent `/var/lib/forgejo` is forgejo-owned, child is uid 70) — cosmetic once the `d` rule sets 70/70.

### References

- Decoder: `docs/debug/forgejo.md`
- `generic/server/forgejo.nix` (tmpfiles rules, container def)
- Prometheus/SSH/Config lane evidence from the 2026-10-16 session; journal: `systemd-tmpfiles[1295290]: Detected unsafe path transition …` at 20:52:56, first `pg_filenode.map` FATAL 20:53:13.
