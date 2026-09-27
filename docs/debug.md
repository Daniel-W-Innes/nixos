# Debugging guide for AI sessions

Playbook for investigating incidents on this infra through the observability stack (mcp-grafana MCP). Written after the 2026-09-03 transmission outage, which took ~25 queries and 8 file parses — following the rules below would have taken ~10.

## Topic index

This file is the index — always read in full. Load a topic file only when the symptom or a lane matches its trigger: **one to three files per incident, never all of them.** Old citations of the form `docs/debug.md` §"<name>" resolve through the *Former heading* column below.

| Trigger — symptom or keyword | Topic file | Former heading |
|---|---|---|
| transmission hung/slow, torrents stalled, RPC timeouts, traefik 499/502, `proton`/`proton-br`, path-MTU, CIFS metadata latency | `docs/debug/transmission.md` | "Transmission specifics that decode symptoms" |
| forgejo down/won't start, `forgejo-db`, postgres crash recovery, runner 503s, dependency-fail, `upholds` | `docs/debug/forgejo.md` | "Forgejo specifics that decode symptoms" |
| journal labels missing/wrong, `unit` label, `init.scope`, `service_name` values, trimmed JSON fields | `docs/debug/journal.md` | "Journal data: live reality vs. repo intent" |
| "is this error real?", constant background errors, podman exporters, `[TTM]`, loki self-echoes, stuck `up=0` targets | `docs/debug/known-noise.md` | "Known noise — ignore, don't chase" |
| units failed after `nixos-rebuild switch`, same-second timeout cluster, container recreation | `docs/debug/switch-storms.md` | "Switch storms: units failed after `nixos-rebuild switch`" |
| LogQL, label discovery, `query_loki_stats`, oversized results, parse script | `docs/debug/loki.md` | "Loki playbook (mcp-grafana)" |
| PromQL, alert rules, `up`/`rate`/`count_over_time` baselines, node_exporter devices, wireguard handshake signals, `activeAt` | `docs/debug/prometheus.md` | "Prometheus playbook (mcp-grafana)" |
| open gaps, expected/pending failures, MTU permanence, broken exporters | `docs/debug/planned-fixes.md` | "Planned fixes (gaps future sessions should expect, not be surprised by)" |
| how a session should go, worked walkthrough, 2026-09-03 timeline | `docs/debug/worked-example.md` | "Worked example (abridged)" |

The sections that stay here (old citations still resolve): **Topology cheat sheet** (hosts table), **Datasource UIDs**, **Time and anchors**, **Workflow rules**.

## Topology cheat sheet

| Host | Role | Notes |
|------|------|-------|
| `melon` | server | Observability stack (Prometheus, Grafana, Loki, Tempo, InfluxDB), traefik, arr stack + transmission, jellyfin, immich, forgejo |
| `onion` | desktop | This Claude session runs here; `mcp-grafana` MCP server runs here as an oci-container |
| `cucamelon` | laptop | Often offline (its exporters show up=0) |
| `pumpkin` | NAS | SMB target for melon's `/mnt/media` (CIFS mount), copyparty |
| `radish` | UniFi controller | unpoller target (currently 401s) |

Symptom decoders for transmission and forgejo live in the topic files above.

## Datasource UIDs (mcp-grafana)

| Datasource | UID |
|---|---|
| Prometheus (default) | `PBFA97CFB590B2093` |
| Loki | `P8E80F9AEF21F6940` |
| Tempo | `P214B5B846CF3925F` |
| InfluxDB | `P951FEA4DE68E13C5` |

## Time and anchors

- Loki timestamps are epoch-ns **UTC**. Journal `MESSAGE` fields (uptime-kuma, gotify, arr logs) carry **local EDT** times (`2026-09-03T21:56:58-04:00`). EDT = UTC−4 (summer). Anchor all arithmetic to a MESSAGE timestamp you can see, not to `now` offsets.
- uptime-kuma journal lines (`|= "MONITOR"`) are the best incident timeline source: they record monitor state changes with local-time stamps and give you both onset and recovery.

## Workflow rules

1. **Baseline before believing.** Any suspicious signal (a new error class, a metric dip) gets one `count_over_time`/range query over ≥10 h before being treated as causal.
2. **Ruled-out list discipline.** For each hypothesis, write the single cheapest query that kills it (e.g. `min_over_time(up{...})` for LAN health; unit-restart check = `systemctl status` or kernel/unit logs). Don't re-litigate dead hypotheses.
3. **Shell access**: `ssh melon` works from onion and is **explicitly allowed** — as daniel, read-only: `journalctl` (wheel), `systemctl status/cat`, mounts, service dirs, `/proc`. Never sudo over ssh (needs an interactive tty). Observability-first still applies: ssh only for what mcp-grafana can't see (live unit definitions, local state, files).
   **When root is needed, make the user a script instead of a command list.** Write it to `/tmp` on the host via an ssh heredoc (`ssh melon 'bash -s' <<'EOF'`), have the user run one `sudo bash /tmp/<script>` (their tty, their password), and have the script tee its output to `/tmp` files you read back over ssh. One sudo per run beats one sudo per line — the 2026-09-19 pattern (debug runs with `--log-level=debug`, per-thread `/proc/<pid>/task/*/stack` captures, unit drop-ins) recovered transmission this way.
4. **zsh on onion**: `===` triggers a glob error — quote markers or use `---`. `python3` is absent — `nix-shell -p python3` (parse script: `docs/debug/loki.md`). `jq` is available.
5. The MCP tool may redact-looking `(removed)` in URLs/API keys it logs — don't rely on log lines for credentials.
