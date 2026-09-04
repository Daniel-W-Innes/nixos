# Journal logs in Loki are missing the `unit` label — deploy stale Alloy config on melon

### Problem

The repo's Alloy config (`generic/server/visibility.nix:181-202`) relabels `__journal__systemd_unit` → `unit` for `loki.source.journal`. But live Loki data (checked 2026-09-04) has labels `hostname`, `job`, `level`, `service_name` — **no `unit` label** — and `service_name` is a constant (`systemd-journal`) rather than the actual unit name. The running Alloy pipeline on melon predates the repo config (last repo edit 2026-08-15).

### Why it matters

Every journal log line is stored as a full 1–2 KB JSON blob (all ~30 journald fields), and without `unit` you cannot filter by service. Any incident investigation must regex-scan 80k–870k lines per query and repeatedly re-query around Loki's 100-line limits. With `unit` live, `{unit="transmission.service"}` answers most questions in one query — roughly a 100× reduction in query cost.

### Fix

1. Rebuild melon so the deployed Alloy config matches the repo: `sudo nixos-rebuild switch --flake .#melon`
2. Restart alloy if needed (`systemctl status alloy` should show the new config time).
3. Verify in Grafana/Explore (or the mcp-grafana MCP): `list_loki_label_names` over `now-1h` should include `unit`, and a query like `{unit="transmission.service"}` should return lines.
4. If `unit` is still absent after deploy, the label is being dropped between Alloy and Loki — investigate `loki.write`/`limits_config` (see `docs/debug.md` for the full live-vs-repo analysis).

### References

- `docs/debug.md` (sections "Journal data: live reality vs. repo intent" and "Planned fixes")
- Incident report from the 2026-09-03 transmission outage (session transcript)
