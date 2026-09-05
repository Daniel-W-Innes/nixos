# Journal logs in Loki are missing the `unit` label — relabel must live inside `loki.source.journal`

### Problem

Live Loki data (checked 2026-09-04) has journal-stream labels `hostname`, `job`, `service_name` — **no `unit` label** — and `service_name` is a constant (`systemd-journal`) rather than the actual unit name. Two stacked causes:

- **Relabel placement bug:** `loki.source.journal` drops all `__journal_*` labels before forwarding to receivers (Alloy v1.16 `tailer.go` relabels internally, then skips any label still prefixed `__`; the docs say the same). The repo's `loki.relabel "journal_labels"` component sat downstream of the source, so its `__journal__systemd_unit` → `unit` rule never fired. Regression: `f6545a8` "loki relabel" (2026-08-02) moved the rules out of the source, where `beb259c` had them in the source's own `relabel_rules`.
- **Stale deploy:** melon's running config diverges from the repo (the live static `service_name` label appears in no commit; alloy process started 2026-08-11).

### Why it matters

Every journal log line is stored as a full 1–2 KB JSON blob (all ~30 journald fields), and without `unit` you cannot filter by service. Any incident investigation must regex-scan 80k–870k lines per query and repeatedly re-query around Loki's 100-line limits. With `unit` live, `{unit="transmission.service"}` answers most questions in one query — roughly a 100× reduction in query cost.

### Fix

1. Move `relabel_rules` into `loki.source.journal` in `generic/server/visibility.nix` and `generic/lokiShipper.nix` (done 2026-09-04; validated with `alloy fmt`).
2. Deploy: `sudo nixos-rebuild switch --flake .#melon` on melon (also `.#onion` for its shipper). systemd restarts alloy since the config store path changes.
3. Verify in Grafana/Explore (or the mcp-grafana MCP): `list_loki_label_names` over `now-5m` should include `unit`, and a query like `{unit="transmission.service"}` should return lines.

### References

- `docs/debug.md` (sections "Journal data: live reality vs. repo intent" and "Planned fixes")
- Incident report from the 2026-09-03 transmission outage (session transcript)
