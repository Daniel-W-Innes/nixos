# Switch storms: units failed after `nixos-rebuild switch`


A flake update bumps nearly every package, so the switch restarts nearly every service — expect a wall of restart traffic in the journal. Signatures:

- **Stop-phase timeout cluster**: unrelated units all "Failed with result 'timeout'" at the *same second* = stop order + 90s (default TimeoutStopSec) — units that wedged on SIGTERM and were SIGKILLed. Most recover when systemd restarts them; the switch's final warning lists only the units still failed.
- **Podman container recreations take minutes** (image pull → create → start; ~5 min for forgejo-db on 2026-09-11). "Container started" ≠ the service inside is ready — anything needing the DB must wait on the socket (see `docs/debug/forgejo.md`).
- **Start-timeout during namespace rebuild**: a daemon confined to a namespace that's being rebuilt (transmission ↔ proton) can time out *starting*; start it again after `proton.service` settles.
- Worked example: the 2026-09-11 storm (forgejo DB race, runner cascade, transmission stop/start wedges) — `docs/issues/done/08-forgejo-db-start-race.md`.

