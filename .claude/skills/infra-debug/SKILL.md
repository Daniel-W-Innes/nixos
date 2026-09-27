---
name: infra-debug
description: Debug incidents on the self-hosted infra (melon/onion services) via the mcp-grafana observability stack. Use when the user reports a service down, slow, or erroring; units failed after nixos-rebuild switch; metric anomalies; or a fired alert. Drives a parallel subagent investigation following the `docs/debug.md` index and its per-symptom topic files under `docs/debug/`.
---

# Infra debugging with subagent fan-out

`docs/debug.md` is the index every session reads: topology, datasource UIDs, time anchoring, workflow rules, and a symptom→topic table. The decoders live in `docs/debug/*.md`. You are the **coordinator**: read the index and the topic files your symptom matches, then delegate the investigation to parallel subagents — each also reads the index plus its assigned topic files. Do not run the sweep yourself — fan out, then verify the decisive claim only.

## Phase 0 — Scope and anchor

1. Read `docs/debug.md` (the index) in full — UIDs, time anchoring, workflow rules, topic table. Then load `docs/debug/known-noise.md` (always — it stops you chasing baselines) plus every topic file the symptom matches: transmission → `docs/debug/transmission.md`; forgejo/runner → `docs/debug/forgejo.md`; post-switch failures → `docs/debug/switch-storms.md`; journal/Loki → `docs/debug/journal.md` + `docs/debug/loki.md`; Prometheus/alerts → `docs/debug/prometheus.md`.
2. Fix the time window: journal MESSAGEs are EDT (−4), Loki timestamps are UTC ns. Anchor to a visible MESSAGE timestamp, or ask the user when they noticed it. Convert once; pass explicit `startRfc3339`/`endRfc3339` to every query (default lookback is only 1 h).
3. Write the hypothesis list (2–5 candidates), each with the single cheapest query that would kill it (`docs/debug.md` §Workflow rules). These become the lanes.

## Phase 1 — Fan out investigators

Spawn all subagents **in one message** so they run concurrently — one per lane. Each prompt must be self-contained and must include:

- The symptom as reported, in the user's words.
- The time window in both UTC and EDT.
- The lane assignment, naming **every topic file that lane reads as a full repo-relative path** (e.g. `docs/debug/journal.md`, `docs/debug/prometheus.md`); if unsure, map the symptom through the index table.
- The datasource UIDs and the instruction to read `docs/debug.md` (index) and the assigned `docs/debug/*.md` files first and obey them.
- The return contract: findings with timestamps, queries actually used, hypotheses ruled out, confidence, and next steps — raw data, no padding.

Standard lanes:

1. **Journal/Loki** (general-purpose agent) — read `docs/debug/journal.md` + `docs/debug/loki.md`: label discovery first (`list_loki_label_names/values`), `query_loki_stats` before any pull, `|=` filters on the JSON blobs; remember systemd's own messages carry no `unit` label (text-filter instead). Goal: first error, restart/failure timeline, stop/start messages.
2. **Prometheus** (general-purpose agent) — read `docs/debug/prometheus.md`: aggregate before pulling: `min_over_time(up{...}[3h])`, `count_over_time` baselines; node_exporter devices `ens3`/`proton-br`; the **eight** provisioned alerts as early-warning shortcuts. Goal: host health (CPU/mem/disk), network health, uptime history.
3. **Config/state** (Explore agent) — repo only: the service's module (`generic/`, `modules/`, `hosts/`), `docs/issues/` and `docs/reports/` for known problems, `docs/debug/planned-fixes.md` for known gaps, recent `git log`. Goal: what the config intends, what changed recently, which known issue matches.
4. **Local state/SSH** (general-purpose agent) — `ssh melon` read-only as daniel (no sudo, never edit files on the host): `systemctl cat/status <unit>` (the *live* unit definition — sandbox props, ExecStart, drops-ins), `journalctl -b -u <unit>`, mount state (`systemctl status '*.mount' '*.automount'`, `mount`), namespace config (`/etc/netns/<ns>/`, `/run/netns/`), service state dirs. Goal: the live reality the repo and metrics can't see — exact unit definitions, local files, mount health.
5. Extra lanes only when the hypothesis list calls for them: **timeline** (uptime-kuma `MONITOR` lines; `docs/debug.md` §Time and anchors), **kernel** (always a second filter — the `[TTM]` noise in `docs/debug/known-noise.md` floods it), **switch-storm** (after a `nixos-rebuild switch`: the `.service: Failed with result` text filter and the stop-phase timeout-cluster signature, `docs/debug/switch-storms.md`), and the **service decoders** (`docs/debug/transmission.md`, `docs/debug/forgejo.md`) whenever the symptom names that service.

Subagent discipline (spell it out in each prompt):

- Baseline before believing: any suspicious signal gets a ≥10 h `count_over_time` before being treated as causal.
- Ignore the noise catalogued in `docs/debug/known-noise.md`; never pull raw windows without a line filter; `limit` ≤ 50.
- Read-only: they may `git log`/grep and `ssh melon` as daniel for local state, but must not edit files (repo or host) and must not sudo.

## Phase 2 — Verify and synthesize

1. Re-run at most the one or two decisive queries yourself to confirm the causal claim (never re-run the sweep the subagents did) — or one read-only ssh check if the claim is local state (a unit file, a mount, a file on disk).
2. Kill remaining hypotheses one query at a time, cheapest first; keep the ruled-out list.
3. Reconstruct the timeline in EDT anchored to MESSAGE timestamps; map each symptom through the matching topic files (`docs/debug/transmission.md`, `docs/debug/forgejo.md`, `docs/debug/switch-storms.md`) to root cause(s) and recovery actions.

## Phase 3 — Report and recover

- Report: timeline, root cause, evidence (queries + key lines), what was ruled out, and exact recovery commands.
- Host access: **SSH is explicitly allowed** — `ssh melon` from onion as daniel, read-only (journalctl, `systemctl status/cat`, mounts, service dirs, `/proc`); never sudo over ssh (sudo needs an interactive tty). Observability-first still applies for anything mcp-grafana already answers.
- **When root is needed, make the user a script instead of a command list.** Write it into `/tmp` on the host over ssh (`ssh melon 'bash -s' <<'EOF'` heredoc), have the user run exactly one `sudo bash /tmp/<script>` (their password, their tty), and have the script write its outputs to `/tmp` files you then read back over ssh. One sudo per run beats one sudo per line — the 2026-09-19 transmission pattern (debug runs with `--log-level=debug`, per-thread `/proc/<pid>/task/*/stack` captures, unit drop-in experiments) recovered the service this way.
- Never commit — leave any config fix as a working-tree diff for the user.
- Offer the repo follow-ups: a `docs/reports/` post-incident write-up, a `docs/issues/` (or `docs/issues/done/`) entry, and a playbook update — append the new decoder to the matching `docs/debug/*.md` file; if it is a new symptom class, create `docs/debug/<topic>.md` **and add its row to the topic table in `docs/debug.md`** — the table is the only router.
