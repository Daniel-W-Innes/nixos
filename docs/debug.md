# Debugging guide for AI sessions

Playbook for investigating incidents on this infra through the observability stack (mcp-grafana MCP). Written after the 2026-09-03 transmission outage, which took ~25 queries and 8 file parses — following the rules below would have taken ~10.

## Topology cheat sheet

| Host | Role | Notes |
|------|------|-------|
| `melon` | server | Observability stack (Prometheus, Grafana, Loki, Tempo, InfluxDB), traefik, arr stack + transmission, jellyfin, immich, forgejo |
| `onion` | desktop | This Claude session runs here; `mcp-grafana` MCP server runs here as an oci-container |
| `cucamelon` | laptop | Often offline (its exporters show up=0) |
| `pumpkin` | NAS | SMB target for melon's `/mnt/media` (CIFS mount), copyparty |
| `radish` | UniFi controller | unpoller target (currently 401s) |

Transmission specifics that decode symptoms:

- `transmission.service` is confined to the `proton` VPN namespace (`generic/server/arr.nix`, `vpnConfinement`). RPC binds `192.168.15.1:9091` *inside* the namespace; the *arrs and uptime-kuma reach it via a main-namespace port mapping on `localhost:9091`.
- Transmission 4.x runs the torrent session, tracker announces, peer I/O, and the RPC server on **one thread**. A blocking network op through the VPN freezes the RPC too → connections *hang* (timeouts), never refuse. A wedged daemon logs nothing (`message-level = 3` only logs errors; blocked ≠ error).
- The VPN namespace itself is **invisible to host exporters**. The only signal is the `proton-br` bridge counter (keepalives) — near-zero rate means the tunnel is dead.
- 2026-09-03 reference incident: transmission RPC dead 21:35–21:56 EDT, self-healed, no restart, correlated with `proton-br` keepalive collapse. Full report: `docs/reports/2026-09-03-transmission-outage.md`.

## Datasource UIDs (mcp-grafana)

| Datasource | UID |
|---|---|
| Prometheus (default) | `PBFA97CFB590B2093` |
| Loki | `P8E80F9AEF21F6940` |
| Tempo | `P214B5B846CF3925F` |
| InfluxDB | `P951FEA4DE68E13C5` |

## Journal data: live reality vs. repo intent

**Always start with `list_loki_label_names` / `list_loki_label_values` and trust what's live, not the config.**

- Live journal-stream labels: `hostname`, `job`, `level`, `service_name`, `unit` (since 2026-09-04). `{unit="transmission.service"}` replaces every regex-scan trick below and makes journal queries ~100× cheaper.
- `service_name` values: `systemd-journal` (all journald lines — added by Alloy's journal source itself, not by config) and `traefik` (OTLP path). `exporter` label: `OTLP` (traefik stream, Loki-side from user-agent).
- Root cause of the missing `unit` (2026-09-04): the journal source drops all `__journal_*` labels before forwarding, so a downstream `loki.relabel` can never set `unit` (regression `f6545a8`). Fixed by declaring rules in `loki.relabel` and assigning its `rules` export to the journal source's `relabel_rules` (`visibility.nix`, `lokiShipper.nix`) — deployed on melon and onion. Bonus fix in the same run: traefik's loki healthcheck was `/ping` (Loki 404s it) → `/ready` (`traefik-targets.nix`), which had been 503-ing the `loki.lc.brotherwolf.ca` route since 2026-08-03, so onion's shipper never landed.
- Each journal line is a **trimmed ~0.4–0.7 KB JSON blob** (14 fields; since 2026-09-04, `loki.process journal_trim` in the alloy configs): keys `MESSAGE`, `PRIORITY`, `SYSLOG_IDENTIFIER`, `_SYSTEMD_UNIT`, `_PID`, `_UID`, `_GID`, `_COMM`, `_TRANSPORT`, `CONTAINER_NAME`, `CONTAINER_ID`, `CODE_FILE`, `CODE_FUNC`, `CODE_LINE` (missing = `null`). Bulk fields (`_CMDLINE`, `_EXE`, `_BOOT_ID`, ...) are dropped at the source. Still prefer the most selective line filter you can; never pull raw windows without one.
- Pass `startRfc3339` (e.g. `now-48h`) to `list_loki_label_names/values` — they only look at recent data by default.

## Known noise — ignore, don't chase

These are constant background noise and will burn queries if treated as signals (baseline first, see §Playbook):

- **`podman-statuspage-exporter`** — "context deadline exceeded" errors every ~10 s, all day. Broken exporter, up=0.
- **`podman-metar-exporter`** — `socket.gaierror: [Errno -3] Try again` on every poll (~8 lines / 10 min, constant). Broken DNS in the container. NOT a network-health signal.
- **kernel `[TTM] Buffer eviction failed`** — every ~15 s (amdgpu VRAM). Floods kernel queries; always add a second filter when querying kernel lines.
- **`prometheus-unpoller-exporter`** — 401 vs radish, nil-pointer panics.
- **`prometheus-shelly-exporter`** — 401 Unauthorized every scrape.
- **`*arr` services** — `SQLite error (5): database is locked` bursts (exportarr contention at each minute tick), Prowlarr 429s from indexers.
- **postgres** — immich/postgres collation-version warnings.
- **grafana** — provisioning-repository "branch protection check" warnings.
- **loki.service** — logs its own queries (`caller=metrics.go`). Any broad regex matches your own query text; expect and discard these lines.
- Broken scrape targets (up=0, pre-existing): `copyparty` (pumpkin:30266), `unpoller`, `shelly`, `statuspage`, all `cucamelon.*`, iperf3 probes between hourly scrapes.

## Loki playbook (mcp-grafana)

1. **Discover labels first.** `list_loki_label_names` → `list_loki_label_values` for the window.
2. **Size-check cheaply.** `query_loki_stats` on the selector before pulling lines.
3. **Narrow windows + `direction="forward"`.** Default is backward + limit — in a chatty window "the 100 newest lines" can cover only 5–20 seconds. If you want the *start* of a window, use forward; if you want a specific moment, bound it tightly (±2 min).
4. **Oversized results get saved to a file** under `~/.claude/projects/-home-daniel-repos-nixos/<session>/tool-results/` when they exceed the token limit. Parse them immediately with the script below (do not use Read — the file is one giant line). The harness requires the full file be read before summarizing; the script does that compactly.
5. **Exclude loki's own query logs** when scanning broadly: append `!= "\"SYSLOG_IDENTIFIER\":\"loki\""`.
6. Prefer `limit` ≤ 50 and the most specific filter that can work: `|=` (substring/regex on the raw line) is enough since the line embeds all journald fields as JSON text.

Parse helper — write to `/tmp/parse_loki.py` (no python3 on onion; use nix-shell):

```python
import json, sys, datetime
obj = json.load(open(sys.argv[1]))
data = obj["data"] if isinstance(obj, dict) else obj
def ts(t):
    return datetime.datetime.fromtimestamp(int(str(t).strip('"'))/1e9, datetime.timezone.utc).strftime("%m-%d %H:%M:%S")
rows = []
for e in data:
    try:
        m = json.loads(e["line"]); msg = m.get("MESSAGE",""); unit = m.get("_SYSTEMD_UNIT","?")
    except Exception:
        msg, unit = e["line"], "?"
    rows.append((e["timestamp"], unit, msg))
rows.sort(key=lambda r: r[0])
seen = {}
for t,u,m in rows:
    seen[m] = seen.get(m,0)+1
    if seen[m]==1: print(ts(t), f"[{u}]", m[:250])
```

Run: `nix-shell -p python3 --run "python3 /tmp/parse_loki.py <saved-file>" | head -150`

## Prometheus playbook (mcp-grafana)

- **Aggregate before you pull.** One number per series beats hundreds of samples:
  - LAN/upstream health: `min_over_time(up{instance=~"onion.*"}[3h])` (4 numbers) instead of a 60 s-step range dump (~700 points).
  - Signal baseline: `sum(count_over_time({service_name="systemd-journal"} |~ "(?i)gaierror" [10m]))` as a range query, step 600 — shows whether an error is constant noise in one call.
- melon = `localhost:*` instances; onion = `onion.lc.brotherwolf.ca:*` (9100 node, 9256 process, 9633 smartctl, 9835 nvidia, 12345 alloy since 2026-09-04 — bound to LAN with pprof off; the alloy UI is served there too, no auth). onion scrapes at 60 s cadence are the cheap LAN-health probe.
- Provisioned Grafana alerts (group `visibility`, folder General, all → gotify): `traefik-backend-down` (`traefik_service_server_up{service=~".*@file"} == 0`), `traefik-down` (`up{job="traefik"} == 0`), `alloy-down` (`up{job="alloy"} == 0`), `alloy-shipping-failing` (`rate(loki_write_batch_retries_total{job="alloy"}[5m]) > 0`). These fire where 2026-09-04's silent failures lived — a gotify ping for any of them replaces the whole investigation this doc was written for.
- Key devices on melon's node_exporter: `ens3` (the only NIC — LAN+WAN), `proton-br` (VPN bridge — only VPN-ns visibility; healthy keepalives ~100–800 B/s depending on activity, near-zero = tunnel dead). 5-min `rate()` smears short events — a 10 min outage shows as ~zero rates at the 5-min samples spanning it.
- `process_exporter` on melon currently has **no namegroups** (exports nothing useful). Planned gap, see backlog.
- Hourly iperf3 probe job (`job="iperf3"`, exporter at localhost:9579) targets cucamelon/onion/pumpkin; the exporter segfaults in musl — treat its results as broken.

## Time and anchors

- Loki timestamps are epoch-ns **UTC**. Journal `MESSAGE` fields (uptime-kuma, gotify, arr logs) carry **local EDT** times (`2026-09-03T21:56:58-04:00`). EDT = UTC−4 (summer). Anchor all arithmetic to a MESSAGE timestamp you can see, not to `now` offsets.
- uptime-kuma journal lines (`|= "MONITOR"`) are the best incident timeline source: they record monitor state changes with local-time stamps and give you both onset and recovery.

## Workflow rules

1. **Baseline before believing.** Any suspicious signal (a new error class, a metric dip) gets one `count_over_time`/range query over ≥10 h before being treated as causal.
2. **Ruled-out list discipline.** For each hypothesis, write the single cheapest query that kills it (e.g. `min_over_time(up{...})` for LAN health; unit-restart check = `systemctl status` or kernel/unit logs). Don't re-litigate dead hypotheses.
3. **Shell access**: `ssh melon` works from onion; daniel is in `wheel` so `journalctl` works without sudo, but `sudo` needs an interactive tty — **the user prefers observability-first (mcp-grafana) over SSH**. Ask before SSHing; don't use sudo.
4. **zsh on onion**: `===` triggers a glob error — quote markers or use `---`. `python3` is absent — `nix-shell -p python3` (see script above). `jq` is available.
5. The MCP tool may redact-looking `(removed)` in URLs/API keys it logs — don't rely on log lines for credentials.

## Planned fixes (gaps future sessions should expect, not be surprised by)

Tracked as GitHub issues in `docs/issues/`:

2. Add `process_exporter` namegroups for transmission/jellyfin/grafana/loki/etc. — `docs/issues/02-process-exporter-namegroups.md`.
3. Add a `wg show latest-handshakes` textfile-collector or tiny exporter for the proton namespace + a Grafana alert on handshake age > 5 min — `docs/issues/03-wireguard-handshake-exporter.md` (the missing signal from the 2026-09-03 incident).
4. Fix/replace the segfaulting iperf3-exporter — `docs/issues/04-iperf3-exporter-segfault.md`.
5. Fix or remove the broken exporters listed in §Known noise — `docs/issues/05-clean-up-broken-exporters.md`.
6. (Resilience, not debug) Transmission watchdog timer — `docs/issues/06-transmission-watchdog.md`.

## Worked example (abridged)

2026-09-03, "transmission on melon stopped working ~50 min ago":

1. `list_loki_label_names` → labels are hostname/job/level/service_name; no unit.
2. Timeline: `{service_name="systemd-journal"} |= "MONITOR"` over ±2 h of the complaint → kuma Down at 21:45:34 EDT, Up at 21:56:55 EDT.
3. Scope: `|= "\"_SYSTEMD_UNIT\":\"lidarr.service\""` etc. → all arrs failing with `DownloadClientUnavailableException` only during that window.
4. Kill hypotheses with one query each: `min_over_time(up{instance=~"onion.*"}[3h])` (LAN fine); `node_load1`/`node_memory_MemAvailable_bytes` (no OOM/CPU cause); kernel lines with a CIFS filter (no mount errors); journal regex for `(vpn|wg-quick|proton)` (no namespace reconfiguration).
5. `rate(node_network_transmit_bytes_total{instance="localhost:9100",device=~"ens3|proton-br"}[5m])` → ens3 collapse during the outage; `proton-br` keepalive degradation bracketing it → VPN tunnel drop froze transmission's single-threaded session (RPC shares the thread).
6. Rule-out misses: metar `gaierror` looked causal but `count_over_time` showed it's constant noise (§Known noise).
