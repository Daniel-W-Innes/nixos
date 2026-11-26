# Lidarr "Unable to communicate with Transmission" — OsPath poison torrent — 2026-11-25

- **Systems affected:** `lidarr.service` on melon — download-client sync (queue + history) blocked for ~7.5 h; UI health showed "Unable to communicate with Transmission."; `transmission.service` unaffected (RPC healthy throughout).
- **Impact:** every `DownloadMonitoringService` poll aborted mid-parse, so the Activity queue and import monitoring were blind from 13:53 to ~21:15 EST. No data loss: the two poisoned torrents were 0-byte metadata-less magnets, and no other download was harmed by this bug (the three sibling Skaggs grabs were stalled by the concurrent tunnel outage, §4).
- **Onset:** 2026-11-25 13:53:39 EST — 5 min 43 s after the poisoned grab landed in Transmission.
- **Recovery:** removed both backslash-named torrents via RPC (`transmission-remote -t 4181 -r`, `-t 4185 -r`, no auth, no root) ~21:15 EST; verified zero new `OsPath` exceptions and zero queue-retrieval warnings in the following poll window. Lidarr never restarted.
- **Status:** resolved. The upstream bug (Lidarr#4293) is unfixed in every release — recurrence is possible whenever a grabbed torrent/magnet name contains a literal backslash. Prevention + optional local patch: `docs/issues/17-lidarr-ospath-poison-torrent.md`.
- **Methodology:** five parallel lanes (Journal/Loki, Prometheus, config/state, local SSH state, upstream research) + one live verification pass. All times EST (UTC−5; DST ended 2026-11-01).

## 1. Executive summary

Lidarr's Transmission client sanitizes only `:` in torrent names (`torrent.Name.Replace(":", "_")` in `TransmissionBase.GetItems`, line 42), then combines the POSIX download dir with the name through `OsPath.op_Addition`. `OsPath.DetectPathKind` classifies any string containing a literal `\` as a **Windows** path, so combining `/mnt/media/downloads/lidarr` (Unix) with a backslash-carrying name throws `Cannot combine OsPaths of different platforms` (OsPath.cs:316). `GetItems()` has no per-torrent try/catch, so **one bad name aborts the enumeration of the entire session** — every poll fails, and `DownloadClientCheck` renders the exception as the exact user-visible string `Unable to communicate with Transmission. Cannot combine OsPaths of different platforms ('/mnt/media/downloads/lidarr' + 'Ricky Skaggs - Waitin\' For The Sun To Shine (1981) flac')` (message template + `ex.Message`; logged only at Debug, which is why it never appears in the journal).

The poison came from the indexer's magnet `dn` field: `dn=Ricky%20Skaggs%20-%20Waitin%5C%27%20For%20...` — a literal, URL-encoded backslash from the uploader's escaped apostrophe (`Waitin\'`). Lidarr searched the clean title at 13:47:34, sent the magnet at 13:47:56, and the first poll after it landed threw at 13:53:39. A second landmine, `My Father\'s Son` (13:50:15, id 4185), was *masked* because enumeration aborts at the first poisoned entry (4181 precedes 4185). 65 identical exceptions by ~21:05, in bursts tied to grabs and monitoring passes (each `Report sent to Transmission` triggers a health re-check ~7 s later).

The fix was removal, not rename: both torrents were metadata-less magnets — added while the PIA tunnel was already dead, so no metadata ever arrived (`totalSize=0`, empty file list) — and Transmission cannot rename the root of a torrent with no file tree (`--rename` → `Error: Invalid argument`). Removal loses nothing. Both removed at ~21:15 EST; the next poll parsed the session cleanly.

## 2. Timeline

| Time (EST) | Event | Source |
|------|-------|--------|
| 2026-11-22 20:09 | Last successful PIA tunnel init (the 2026-11-22 move) | journal |
| **2026-11-25 10:21:41** | **PIA tunnel dies** (`SIGUSR1[soft,ping-restart]` → endless TLS-negotiation failures to 140.228.24.161:1197; 230 TLS errors today, never recovers) | journal |
| 10:32 | `pia-port-forward` starts failing (curl timeout → `Could not resolve host` from 10:45 — ns DNS goes through the tunnel) | journal |
| 13:47:56 | Lidarr grabs ExtraTorrent.st release; magnet `dn` carries the literal `\` → transmission torrent 4181 | journal/RPC |
| 13:50:15 | Second poisoned grab, `My Father\'s Son` → torrent 4185 | RPC |
| **13:53:39** | **First `Cannot combine OsPaths` exception** on the routine `DownloadMonitoringService` poll | journal |
| 13:53–21:05 | 65 identical exceptions (all one torrent), bursty; each new grab re-triggers the health check ~7 s later | Loki |
| 20:53:58 | Last exception before the report | Loki |
| ~21:15 | Both torrents removed via RPC; zero new OsPath errors and zero queue-retrieval warnings in the following poll window | ssh |

## 3. Root causes and fixes

| # | Root cause | Fix | Where |
|---|-----------|-----|-------|
| 1 | Lidarr upstream bug: `GetItems` sanitizes only `:`, `OsPath.DetectPathKind` treats any name containing `\` as Windows, and there is no per-torrent try/catch — one poisoned name aborts the whole sync. Open since 2023 (Lidarr#4293); present in 3.1.0.4875 (installed), latest stable 3.1.6.5079, and `develop` | **Done:** removed the two poisoned torrents. **Pending (optional):** release profile "Must Not Contain" a backslash; local `OsPath` patch via overlay | `docs/issues/17-lidarr-ospath-poison-torrent.md` |
| 2 | Poison source: the indexer's magnet `dn` embeds the uploader's escaped apostrophe (`%5C%27`) | Blocklist the release in Lidarr; report the bad title to the indexer | — |
| 3 | Concurrent tunnel outage kept the five Skaggs grabs at 0 bytes — nothing lost, but also nothing recoverable until the tunnel returns | Separate incident, still open: regenerate the pinned `.ovpn` endpoint | `docs/issues/18-pia-endpoint-rotation-tunnel-outage.md` |

### Ruled out

- Transmission outage/wedge — daemon up 3 days, `num_procs`=1, `changes[48h]`=0, RPC 409, uptime-kuma 34–62 ms, zero traefik 499/502
- CIFS stall — 8 ms cold stat on `/mnt/media/downloads/lidarr` (the 2026-09-18 class)
- Host resources — 64 cores, load 2.9–9.3, ~32 GB free, both filesystems ~25% free
- Tunnel as cause of the OsPath error — the exception is a post-RPC parse failure (the response arrived and was being decoded); onset 3.5 h after the tunnel died
- Restarts / switch storms — lidarr `NRestarts=0`, no rebuild lines, stable PIDs
- exportarr load — exporter stopped on melon post-2026-11-02; queue small
- Multiple poisoned torrents — `|= "Cannot combine OsPaths" != "Waitin"` → 0 hits (the second landmine was masked, and was removed in the same pass)

### Key evidence

```
# Live stack from melon's journal (the decisive artifact):
[Warn] DownloadMonitoringService: Unable to retrieve queue and history items from Transmission
System.Exception: Cannot combine OsPaths of different platforms ('/mnt/media/downloads/lidarr' + 'Ricky Skaggs - Waitin\' For The Sun To Shine (1981) flac')
   at NzbDrone.Common.Disk.OsPath.op_Addition(OsPath left, OsPath right) in ./NzbDrone.Common/Disk/OsPath.cs:line 316
   at NzbDrone.Core.Download.Clients.Transmission.TransmissionBase.GetItems() in ./NzbDrone.Core/Download/Clients/Transmission/TransmissionBase.cs:line 42
   at NzbDrone.Core.Download.TrackedDownloads.DownloadMonitoringService.ProcessClientDownloads(IDownloadClient) in ./NzbDrone.Core/Download/TrackedDownloads/DownloadMonitoringService.cs:line 93

# The poison, in transmission's RPC (magnet dn, URL-encoded backslash):
dn=Ricky%20Skaggs%20-%20Waitin%5C%27%20For%20The%20Sun%20To%20Shine%20%281981%29%20flac

# Cadence over 48 h (Loki count_over_time, hourly): 65 total, all one torrent
19:00Z=3  20:00Z=15  21:00Z=10  22:00Z=15  23:00Z=12  00:00Z=3  01:00Z=1  02:00Z=6
```

## 4. Second incident (still open): PIA tunnel down since 10:21:41 EST

Diagnosed in the same session, orthogonal to the OsPath bug. The `.ovpn` in `secrets/pia-vpn.age` pins `140.228.24.161:1197` (montreal429); neither `montreal429` nor the IP exists in PIA's current server list (checked 21:10 EST — a different Montreal PF server, 107.182.119.118, does), matching the sudden ping-restart after 3 stable days and 11 h of unanswered handshakes. Torrent traffic is at ~0.04% of baseline; RPC is unaffected (veth-local), which is why Lidarr kept talking to Transmission throughout. Recovery: replace the `.ovpn` in the secret with a fresh PIA config and `nixos-rebuild switch` — full details in `docs/issues/18-pia-endpoint-rotation-tunnel-outage.md`. Note the stall alert was blind: the openvpn exporter has been down ≥7 days, so `pia-tunnel-stalled` sat in NoData→OK the whole time.

## 5. Follow-ups

- **User actions (Lidarr UI):** System → Tasks → Check Health to clear the stale health badge (the journal-level failure cleared on the first poll after removal); Activity → remove/blocklist the two releases to prevent a re-grab of the same poisoned `dn`; the three remaining Skaggs magnets are harmless (clean names) but will only download once the tunnel is fixed.
- **Docs done:** this report; `docs/issues/17-lidarr-ospath-poison-torrent.md`; `docs/issues/18-pia-endpoint-rotation-tunnel-outage.md`; decoder sections in `docs/debug/lidarr.md` and `docs/debug/transmission.md`; topic-table row updated in `docs/debug.md`; `docs/debug/planned-fixes.md` entries 17/18.
- **Tunnel recovery:** pending user action (secret edit + switch on melon) — `docs/issues/18`.
