# Lidarr OsPath poison torrent — literal backslash in a torrent/magnet name blocks the whole download-client sync

**Operationally resolved; class open upstream.** 2026-11-25 incident: `docs/reports/2026-11-25-lidarr-poison-torrent.md`.

### Problem

Any Transmission torrent whose name contains a literal `\` makes Lidarr's `OsPath.DetectPathKind` classify the name as a Windows path; combining it with the POSIX download dir in `TransmissionBase.GetItems()` (`outputPath + torrent.Name.Replace(":", "_")` — colons only) throws `Cannot combine OsPaths of different platforms` at `OsPath.cs:316`. With no per-torrent try/catch, one poisoned name aborts the entire `GetItems()` enumeration, so every `DownloadMonitoringService` poll fails and the health check reports "Unable to communicate with <client>." — while Transmission itself is fine. Upstream: [Lidarr#4293](https://github.com/Lidarr/Lidarr/issues/4293) (open since 2023), corroborated by Radarr#11244; the buggy `DetectPathKind` and colon-only sanitization are still in latest stable 3.1.6.5079 and `develop` — upgrading is not a fix.

The 2026-11-25 instance: an ExtraTorrent.st magnet's `dn` carried the uploader's escaped apostrophe (`Waitin%5C%27`), poisoning every poll from 13:53:39 EST until the torrents (ids 4181, 4185 — the second masked because enumeration aborts at the first) were removed at ~21:15 EST.

### Status

- Removed both poisoned torrents via RPC 2026-11-25 (~21:15 EST); verified zero new OsPath exceptions. Root rename was impossible — both were metadata-less magnets (no file tree; `--rename` → Invalid argument).
- Open recurrence vector: any future grab whose magnet `dn` or metadata name contains `\`.

### To do

- [ ] Prevention: Lidarr release profile "Must Not Contain" a backslash term (regex `\\`) — imperfect: indexer titles do not always match the magnet `dn`.
- [ ] Optional true fix: overlay Lidarr and drop the bare-backslash heuristic from `OsPath.DetectPathKind` (keep drive-letter/UNC detection; a lone `\` is a legal filename character on Linux) — one-line, Linux-only-safe, upstream PR-worthy.
- [ ] On the next "Unable to communicate" symptom, check first with `transmission-remote -l | grep -F '\'` (decoder in `docs/debug/lidarr.md`).

### References

- `docs/reports/2026-11-25-lidarr-poison-torrent.md`
- `docs/debug/lidarr.md`
- https://github.com/Lidarr/Lidarr/issues/4293
- https://github.com/Radarr/Radarr/issues/11244
