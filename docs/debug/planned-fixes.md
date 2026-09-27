# Planned fixes (gaps future sessions should expect, not be surprised by)


Tracked as GitHub issues in `docs/issues/`:

3. ~~Add a `wg show latest-handshakes` textfile-collector or tiny exporter for the proton namespace + a Grafana alert on handshake age > 5 min~~ — DONE 2026-09-05: MindFlavor wireguard exporter inside the proton ns (`docs/issues/done/03-wireguard-handshake-exporter.md`). Remaining gap: handshakes don't cover the data plane (2026-09-18 incident) — `docs/issues/done/09-transmission-start-wedge.md`.
4. ~~Fix/replace the segfaulting iperf3-exporter~~ — DONE 2026-09-05: hourly timer + node_exporter textfile collector (`generic/server/iperf-probe.nix`) — `docs/issues/done/04-iperf3-exporter-segfault.md`.
5. Fix or remove the broken exporters listed in `docs/debug/known-noise.md` — `docs/issues/05-clean-up-broken-exporters.md`.
6. (Resilience, not debug) Transmission watchdog timer — `docs/issues/06-transmission-watchdog.md`.
7. ~~(2026-09-19) Transmission start-wedge after unclean power-off~~ — RESOLVED: two stacked environmental faults (path-MTU shrink → `MTU = 1300`; degraded CIFS session → remount), `docs/issues/done/09-transmission-start-wedge.md`. Repo mitigations: `Restart=on-failure` + `TimeoutStartSec=600` in `arr.nix`, `== bool 0` alert fix in `visibility.nix`. Pending: MTU permanence in `proton-vpn.age`; pumpkin metadata-latency investigation.
10. ~~Forgejo stranded after reboot: `podman-forgejo-db` boot-failure (podman contention) cancels forgejo's start job via `requires` and it's never re-queued~~ — DONE 2026-09-27: `upholds=` fix committed (`cf9faf0`) and deployed; reboot verification pending — `docs/issues/done/10-forgejo-dependency-fail-after-reboot.md`.
11. Lidarr CPU spin (thread-pool starvation, ~1172% CPU / 11.1G RSS) is the boot-time SQLite-lock contention engine behind the 2026-09-27 failure — `docs/issues/11-lidarr-cpu-spin.md`.
12. Postgres unclean shutdown every stop: `podman stop` 10s default SIGKILLs postgres mid-shutdown — `--stop-timeout=90` fix in `forgejo.nix` (2026-09-27, deployed; verification pending) — `docs/issues/12-postgres-unclean-shutdown.md`.

