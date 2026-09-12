# Forgejo stranded after switch — DB start race, runner cascade, transmission wedges

**DONE 2026-09-11.** A flake-update switch on melon restarted nearly everything, and three units stayed failed: forgejo lost a start race against its own postgres container and burned its start-limit retries before the DB socket existed; gitea-runner-melon was a cascade (503 crash-loop while forgejo was down); transmission wedged twice (stop-timeout of the old daemon, then start-timeout of the replacement while the proton namespace rebuilt). Forgejo fix shipped in `generic/server/forgejo.nix`: wait-for-psql as `mkBefore` the module's migrate, admin-create as `mkAfter`, `TimeoutStartSec=600`. Transmission needed only a manual start once the namespace settled — no config change.

### Problem

2026-09-11 `nixos-rebuild switch` on melon (nixpkgs bump, forgejo 16.0.3). Timeline (EDT):

- 20:51:40 the switch stops the `forgejo-db` podman container; its recreation (image pull → create → start) takes ~5 min, with postgres accepting connections only at 20:56:50.
- 20:52:41 a cluster of unrelated units (jellyfin, dawarich-web, immich-ml, prowlarr/sonarr/radarr, transmission) all fail "with result 'timeout'" at the same second — stop order + 90s TimeoutStopSec: they wedged on SIGTERM and were SIGKILLed. All recovered except transmission.
- 20:56:13–15 the new forgejo starts; the module's preStart runs `forgejo migrate`, which fails 4× in ~2s with `dial unix /run/forgejo-db/.s.PGSQL.5432: connect: no such file or directory`, hits the start-limit, and stays failed. Our existing psql wait-loop ran *after* the module's migrate in the merged preStart, so it never got a chance.
- From 20:53:47 gitea-runner-melon crash-loops: `fail to invoke Declare: unavailable: 503 Service Unavailable` every ~2.5s (traefik up, forgejo backend down). onion's runner also 503s (`failed to fetch task`) but stays alive retrying.
- 21:01:03 the replacement transmission also fails: "start operation timed out" (it started while the proton VPN namespace was being rebuilt; proton-up succeeded 20:53:47), then `State 'stop-sigterm' timed out. Killing.` → SIGKILL.

### Fix

- `generic/server/forgejo.nix`: `preStart` is `types.lines` — definitions merge as strings, sorted by mkBefore/mkAfter priority (500/1000/1500). Split ours into `lib.mkBefore` (psql wait-loop) and `lib.mkAfter` (admin user create), so the module's setup/migrate lands between them. Raised `serviceConfig.TimeoutStartSec = 600` — the default 90s would kill the wait mid-DB-restart; `Restart=always` (module default) covers anything longer without hitting the start-limit, since attempts then land ~10 min apart.
- Transmission: no config change; start it after the namespace settles. The stop-wedge is also fresh evidence for the watchdog in `docs/issues/06-transmission-watchdog.md`.
- Night-of recovery: `systemctl start forgejo gitea-runner-melon transmission` once DB and namespace were back.

### Verification

- `nix eval .#nixosConfigurations.melon.config.systemd.services.forgejo.preStart` shows the merged script in order: wait-loop → forgejo_setup/migrate/regenerate hooks/keys → admin-create.
- Generated unit (`systemd.units."forgejo.service".unit`) carries `TimeoutStartSec=600`, `Restart=always`, single ExecStartPre script.
- `nix flake check` passes.
- Deploy pending as of writing (next switch on melon). To re-exercise the scenario: switch while the `forgejo-db` container is down; forgejo should wait and come up on its own.

### References

- `docs/debug.md` §"Switch storms", §Forgejo specifics, §Transmission specifics, §Journal data
- Evidence: Loki `{unit="forgejo.service"}`, `{unit="podman-forgejo-db.service"}`, `{unit="gitea-runner-melon.service"}`, `{service_name="systemd-journal"} |= ".service: Failed with result"` over 2026-09-12T00:50–01:08Z
