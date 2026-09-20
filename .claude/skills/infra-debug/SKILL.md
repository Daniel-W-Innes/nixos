---
name: infra-debug
description: Debug incidents on the self-hosted infra (melon/onion services) via the mcp-grafana observability stack. Use when the user reports a service down, slow, or erroring; units failed after nixos-rebuild switch; metric anomalies; or a fired alert. Drives a parallel subagent investigation following docs/debug.md.
---

# Infra debugging with subagent fan-out

`docs/debug.md` is the authoritative playbook: topology, datasource UIDs, known noise, and per-service symptom decoders. You are the **coordinator**: read the doc once, then delegate the investigation to parallel subagents. Do not run the sweep yourself — fan out, then verify the decisive claim only.

## Phase 0 — Scope and anchor

1. Read `docs/debug.md` in full. Note the Loki (`P8E80F9AEF21F6940`) and Prometheus (`PBFA97CFB590B2093`) UIDs, the §Known noise list, and any decoder matching the symptom (transmission, forgejo, switch storms).
2. Fix the time window: journal MESSAGEs are EDT (−4), Loki timestamps are UTC ns. Anchor to a visible MESSAGE timestamp, or ask the user when they noticed it. Convert once; pass explicit `startRfc3339`/`endRfc3339` to every query (default lookback is only 1 h).
3. Write the hypothesis list (2–5 candidates), each with the single cheapest query that would kill it (debug.md §Workflow rules). These become the lanes.

## Phase 1 — Fan out investigators

Spawn all subagents **in one message** so they run concurrently — one per lane. Each prompt must be self-contained and must include:

- The symptom as reported, in the user's words.
- The time window in both UTC and EDT.
- The lane assignment with the debug.md sections that apply.
- The datasource UIDs and the instruction to read `docs/debug.md` first and obey it.
- The return contract: findings with timestamps, queries actually used, hypotheses ruled out, confidence, and next steps — raw data, no padding.

Standard lanes:

1. **Journal/Loki** (general-purpose agent) — label discovery first (`list_loki_label_names/values`), `query_loki_stats` before any pull, `|=` filters on the JSON blobs; remember systemd's own messages carry no `unit` label (text-filter instead, §Journal data). Goal: first error, restart/failure timeline, stop/start messages.
2. **Prometheus** (general-purpose agent) — aggregate before pulling: `min_over_time(up{...}[3h])`, `count_over_time` baselines; node_exporter devices `ens3`/`proton-br`; the four provisioned alerts (§Prometheus playbook) as early-warning shortcuts. Goal: host health (CPU/mem/disk), network health, uptime history.
3. **Config/state** (Explore agent) — repo only: the service's module (`generic/`, `modules/`, `hosts/`), `docs/issues/` and `docs/reports/` for known problems, recent `git log`. Goal: what the config intends, what changed recently, which known issue matches.
4. **Local state/SSH** (general-purpose agent) — `ssh melon` read-only as daniel (no sudo, never edit files on the host): `systemctl cat/status <unit>` (the *live* unit definition — sandbox props, ExecStart, drops-ins), `journalctl -b -u <unit>`, mount state (`systemctl status '*.mount' '*.automount'`, `mount`), namespace config (`/etc/netns/<ns>/`, `/run/netns/`), service state dirs. Goal: the live reality the repo and metrics can't see — exact unit definitions, local files, mount health.
5. Extra lanes only when the hypothesis list calls for them: **timeline** (uptime-kuma `MONITOR` lines), **kernel** (always a second filter — TTM noise floods it), **switch-storm** (after a `nixos-rebuild switch`: the `.service: Failed with result` text filter and the stop-phase timeout-cluster signature, §Switch storms).

Subagent discipline (spell it out in each prompt):

- Baseline before believing: any suspicious signal gets a ≥10 h `count_over_time` before being treated as causal.
- Ignore §Known noise; never pull raw windows without a line filter; `limit` ≤ 50.
- Read-only: they may `git log`/grep and `ssh melon` as daniel for local state, but must not edit files (repo or host) and must not sudo.

## Phase 2 — Verify and synthesize

1. Re-run at most the one or two decisive queries yourself to confirm the causal claim (never re-run the sweep the subagents did) — or one read-only ssh check if the claim is local state (a unit file, a mount, a file on disk).
2. Kill remaining hypotheses one query at a time, cheapest first; keep the ruled-out list.
3. Reconstruct the timeline in EDT anchored to MESSAGE timestamps; map each symptom through the debug.md decoders (§Topology specifics, §Switch storms) to root cause(s) and recovery actions.

## Phase 3 — Report and recover

- Report: timeline, root cause, evidence (queries + key lines), what was ruled out, and exact recovery commands.
- Host access: **SSH is explicitly allowed** — `ssh melon` from onion as daniel, read-only (journalctl, `systemctl status/cat`, mounts, service dirs, `/proc`); never sudo over ssh (sudo needs an interactive tty). Observability-first still applies for anything mcp-grafana already answers.
- **When root is needed, make the user a script instead of a command list.** Write it into `/tmp` on the host over ssh (`ssh melon 'bash -s' <<'EOF'` heredoc), have the user run exactly one `sudo bash /tmp/<script>` (their password, their tty), and have the script write its outputs to `/tmp` files you then read back over ssh. One sudo per run beats one sudo per line — the 2026-09-19 transmission pattern (debug runs with `--log-level=debug`, per-thread `/proc/<pid>/task/*/stack` captures, unit drop-in experiments) recovered the service this way.
- Never commit — leave any config fix as a working-tree diff for the user.
- Offer the repo follow-ups: a `docs/reports/` post-incident write-up, a `docs/issues/` (or `docs/issues/done/`) entry, and a `docs/debug.md` update with any new decoder learned.
