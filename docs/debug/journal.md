# Journal data: live reality vs. repo intent


**Always start with `list_loki_label_names` / `list_loki_label_values` and trust what's live, not the config.**

- Live journal-stream labels: `hostname`, `job`, `level`, `service_name`, `unit` (since 2026-09-04). `{unit="transmission.service"}` replaces every regex-scan trick below and makes journal queries ~100× cheaper.
- **systemd's own messages carry no `unit` label**: "Failed with result"/"Starting"/"Stopped"/kill lines are logged by PID 1 with `_SYSTEMD_UNIT=init.scope`. Find unit failures by text instead: `{service_name="systemd-journal"} |= ".service: Failed with result"` (all services), or `|= "transmission.service"` for one unit (the name appears in the MESSAGE).
- `service_name` values: `systemd-journal` (all journald lines — added by Alloy's journal source itself, not by config) and `traefik` (OTLP path). `exporter` label: `OTLP` (traefik stream, Loki-side from user-agent).
- Root cause of the missing `unit` (2026-09-04): the journal source drops all `__journal_*` labels before forwarding, so a downstream `loki.relabel` can never set `unit` (regression `f6545a8`). Fixed by declaring rules in `loki.relabel` and assigning its `rules` export to the journal source's `relabel_rules` (`generic/server/visibility.nix`, `generic/lokiShipper.nix`) — deployed on melon and onion. Bonus fix in the same run: traefik's loki healthcheck was `/ping` (Loki 404s it) → `/ready` (`generic/server/traefik-targets.nix`), which had been 503-ing the `loki.lc.brotherwolf.ca` route since 2026-08-03, so onion's shipper never landed.
- Each journal line is a **trimmed ~0.4–0.7 KB JSON blob** (14 fields; since 2026-09-04, `loki.process journal_trim` in the alloy configs): keys `MESSAGE`, `PRIORITY`, `SYSLOG_IDENTIFIER`, `_SYSTEMD_UNIT`, `_PID`, `_UID`, `_GID`, `_COMM`, `_TRANSPORT`, `CONTAINER_NAME`, `CONTAINER_ID`, `CODE_FILE`, `CODE_FUNC`, `CODE_LINE` (missing = `null`). Bulk fields (`_CMDLINE`, `_EXE`, `_BOOT_ID`, ...) are dropped at the source. Still prefer the most selective line filter you can; never pull raw windows without one.
- Pass `startRfc3339` (e.g. `now-48h`) to `list_loki_label_names/values` — they only look at recent data by default.

