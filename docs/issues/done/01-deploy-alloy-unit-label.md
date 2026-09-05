# Journal logs in Loki are missing the `unit` label — relabel must live inside `loki.source.journal`

**DONE 2026-09-04.** Verified live on both hosts: journal lines carry `unit`/`level`/`hostname` labels and the trimmed 14-field JSON; traefik's loki route is healthy; both alloys are scraped by melon's Prometheus.

### Problem

Live Loki data (checked 2026-09-04) has journal-stream labels `hostname`, `job`, `service_name` — **no `unit` label** — and `service_name` is a constant (`systemd-journal`) rather than the actual unit name. Two stacked causes:

- **Relabel placement bug:** `loki.source.journal` drops all `__journal_*` labels before forwarding to receivers (Alloy v1.16 `tailer.go` relabels internally, then skips any label still prefixed `__`; the docs say the same). The repo's `loki.relabel "journal_labels"` component sat downstream of the source, so its `__journal__systemd_unit` → `unit` rule never fired. Regression: `f6545a8` "loki relabel" (2026-08-02) moved the rules out of the source, where `beb259c` had them in the source's own `relabel_rules`. Note for v1.16: the source's `relabel_rules` is a **capsule** — it must be assigned `loki.relabel.<name>.rules` (a component declaring `rule {}` blocks); neither block syntax (`"must be an attribute"`) nor an inline array (`"should be capsule, got array"`) loads. `alloy fmt` accepts all three, so validate by actually running alloy.
- **Stale deploy:** melon's running config diverges from the repo (the live static `service_name` label appears in no commit; alloy process started 2026-08-11).
- **Traefik route 503:** `traefik-targets.nix` gave the loki target `pingHealthCheck` (`/ping`), an endpoint Loki doesn't serve (404) — grafana/forgejo only pass theirs via 302/303 redirects. Traefik marked the loki server unhealthy (`traefik_service_server_up{service="loki@file"}` = 0 while all others = 1) and returned 503 to every push to `loki.lc.brotherwolf.ca`, so onion's shipper never landed a single line in Loki (0 `{hostname="onion"}` lines in 24h). Fixed 2026-09-04: healthcheck path → `/ready`.

### Why it matters

Every journal log line is stored as a full 1–2 KB JSON blob (all ~30 journald fields), and without `unit` you cannot filter by service. Any incident investigation must regex-scan 80k–870k lines per query and repeatedly re-query around Loki's 100-line limits. With `unit` live, `{unit="transmission.service"}` answers most questions in one query — roughly a 100× reduction in query cost.

### Fix

1. In `generic/server/visibility.nix` and `generic/lokiShipper.nix`: declare a `loki.relabel "journal_rules"` component (with `forward_to = []`, only used for its export) and assign its `rules` export to the journal source's `relabel_rules` (done 2026-09-04; validated by running alloy against the built config, not just `alloy fmt`).
2. Deploy on melon: `sudo nixos-rebuild switch --flake .#melon` — ships both the alloy `relabel_rules` fix and the traefik healthcheck fix (`/ping` → `/ready`) that was 503-ing the `loki.lc.brotherwolf.ca` route, so onion's shipper couldn't reach Loki at all. Onion already switched (2026-09-04, verified running); no further onion action needed once traefik marks loki up (≤10 s after switch).
3. Verify in Grafana/Explore (or the mcp-grafana MCP): `list_loki_label_names` over `now-5m` should include `unit`, and a query like `{unit="transmission.service"}` should return lines.

### References

- `docs/debug.md` (sections "Journal data: live reality vs. repo intent" and "Planned fixes")
- Incident report from the 2026-09-03 transmission outage (session transcript)
