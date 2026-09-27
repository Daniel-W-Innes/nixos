# Lidarr CPU spin — thread-pool starvation, boot-time contention engine

**Open.** Opened 2026-09-27. Suspected aggravator of `docs/issues/done/10-forgejo-dependency-fail-after-reboot.md`.

### Problem

On the 2026-09-27 boot, `lidarr.service` came up with its process at ~1172% CPU, 11.1 G RSS, 310 tasks, logging "thread pool starvation"; it owns 488 of the 878 `database is locked` errors recorded in that boot's journal (Sonarr 169, grafana-start 128, navidrome 58, Radarr 26, Prowlarr 6, …). That SQLite/podman-boltdb contention storm is what killed `podman-forgejo-db`'s first post-boot run (exit 126) and also InfluxDB's and meilisearch-ui's first starts. Zero podman start failures in the 12 h before the reboot, so the storm is boot-specific — but it recurs on every boot until the spin source is fixed.

Contributing: `lidarr-search-drip.service` failed at 10:08:24 (exit 7, timer-triggered). The drip's curl had no `--max-time` at the time of that failure — the fix (`ade1d74`, `RuntimeMaxSec=1800` + `--max-time 60`) is now on master (in `generic/server/lidarr-search-drip.nix`) and in melon's 2026-09-27 11:48 switch generation; a 67 h runaway drip was documented on 2026-09-24. Note melon booted a 12-day-old closure on 09-27, so the fix wasn't live at that boot.

### To do

- ~~Merge `ade1d74` (lidarr drip `--max-time`) and deploy.~~ — done 2026-09-27: merged (ancestor of `2d01856`) and in melon's 09-27 switch generation.
- Investigate the lidarr thread-pool starvation itself: is it the drip runaway, a bad indexer connection, or a `/mnt/media` CIFS stall (the 2026-09-18 mechanism)?
- Re-examine after the next reboot whether boot-time `database is locked` storms subside (baseline: 878 errors this boot).

### References

- `docs/reports/2026-09-27-forgejo-dependency-outage.md` §4.2
- `generic/server/lidarr-search-drip.nix`
- `docs/issues/done/09-transmission-start-wedge.md` (CIFS metadata-stall precedent)
