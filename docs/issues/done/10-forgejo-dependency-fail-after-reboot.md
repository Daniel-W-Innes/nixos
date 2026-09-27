# Forgejo stranded after reboot — dependency-fail on podman-forgejo-db never retried

**DONE 2026-09-27.** Fix committed in `cf9faf0` (`upholds=` beside `requires` in `generic/server/forgejo.nix`) and deployed to melon with the 2026-09-27 switch; reboot verification pending.

### Problem

A clean reboot of melon (2026-09-25 19:25 and again 2026-09-27 10:04, both user-initiated) makes `podman-forgejo-db.service` fail its first boot attempt: boot-time container-start contention (11 containers created in 12 min, 878 `database is locked` errors across containers) produces a conmon exit-file ENOENT and a podman boltdb `database is locked` on state save → the unit fails with exit 126. `forgejo.service`'s `Requires=` on the DB unit then cancels its start job (`result 'dependency'`), and systemd **never re-queues a dependency-failed job** (`Restart=always` only covers a running process exiting). The DB's own `Restart=` recovers ~22 s later; forgejo stays down indefinitely (~39.5 h on 09-27). The 09-11 fix (psql wait-loop `mkBefore` migrate, `TimeoutStartSec=600`) guards a *slow* DB, not a *failed* DB unit — new failure mode, same symptom class as `docs/issues/done/08-forgejo-db-start-race.md`. Full write-up: `docs/reports/2026-09-27-forgejo-dependency-outage.md`.

### Fix

`generic/server/forgejo.nix`: add `upholds = [ "${config.virtualisation.oci-containers.backend}-forgejo-db.service" ]` beside the existing `requires`. When the DB unit comes up via its own `Restart=`, systemd re-queues forgejo's start job; `requires` still propagates failures. Requires systemd ≥ 249 (fine on NixOS 26.05).

### Verification plan

- ✓ Verified 2026-09-27: `nix eval` shows `systemd.services.forgejo.upholds` = `["podman-forgejo-db.service"]` in the generated unit.
- Rehearse (pending): stop the DB unit while forgejo is running (forgejo stops too), start the DB again → forgejo should start on its own.
- Reboot check (pending): melon has not rebooted since the fix was deployed — after the next boot confirm forgejo comes up without manual intervention.

### References

- `docs/reports/2026-09-27-forgejo-dependency-outage.md`
- `docs/debug/forgejo.md`
- Related: `docs/issues/11-lidarr-cpu-spin.md` (the boot-time contention engine)
