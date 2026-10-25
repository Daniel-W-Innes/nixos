# Schema drift: exporter looks green, data is frozen

Symptom class: an exporter consumes a structured upstream stream (SSE/JSON/API), the upstream changes a field name or format, and the exporter silently drops every payload while its liveness signals stay green. Canonical case: the konnected outage, 2026-09-03 → 2026-10-25 (`docs/reports/2026-10-25-konnected-schema-drift.md`).

## Signature (all of these at once)

- `up{job="..."}=1` and `connected`/`last_update_timestamp` fresh — but those are driven by a *separate* heartbeat channel (for konnected: `ping` SSE events), not the data channel
- the data metric is frozen (`entity_state_timestamp`) or absent — `absent(konnected_entity_state_timestamp)` = 1
- a scrape-health gauge dips periodically instead of a hard 0 (konnected `scrape_ok`: 0 for ~10 s once per minute = one failing batch per minute; 6 h average ≈ 0.833)
- exporter journal repeats one parse error ~1/min: `unknown event type: ""` (konnected), or an unmarshal error naming a missing field
- downstream sink sees **zero writes AND zero failed writes** — the write path is never reached (konnected: influxdb `/api/v2/write` counter flat)
- no restarts, no crashes: `NRestarts=0` — the exporter treats upstream parse errors as retryable and loops forever

## Decoder

1. **Capture the live upstream payload and diff it against the exporter's structs.** For konnected:
   `ssh melon 'curl -sN -m 25 http://alarm.lc.brotherwolf.ca/events'` — dump the `data:` lines, then compare field names against the Go structs in `modules/konnected-exporter/main.go` (`State.NameID json:"name_id"` vs the stream's `"id"`). One 25 s capture settled the whole incident.
2. **Read the exporter's own error verbatim** — it names the failed branch: `unknown event type: ""` = the dispatch key was empty (`main.go` splits `state.NameID` and hits the `default:` arm). The quoted string is the parsed value that fell through.
3. **Onset**: first error burst in Loki — `sum(count_over_time({hostname="melon"} |= "konnected-exporter" |= "unknown event type" [1h]))` over the candidate window; the error starts at a panel reboot (`Error subscribing ... connection reset by peer` + `konnected_uptime_seconds` reset in the same minute). Zero errors before, 22 in the first second (full state snapshot), then ~1/min — that shape means the upstream *booted* into the new schema, so the firmware/config changed at the reboot.
4. **Why nobody noticed**: no alert or uptime-kuma monitor covers this feed. `up`, `connected`, and `last_update_timestamp` are ping-driven; `/healthz` checks only Gotify and InfluxDB, never the SSE connection. For the outage to be silently multi-month is expected, not surprising.

## Konnected specifics

- `konnected_uptime_seconds` is the **panel's** uptime (from ping events), not the exporter's — resets mean panel reboots.
- The exporter keeps `LastState` (→ `entity_state_timestamp`) in memory only: an exporter restart after the break clears it, so the dashboard entity panel goes from stale to "No data" at the restart, and the info gauges (`device_id`, `esphome_version`, …) go empty. Both are *aftermath*, not onset.
- The text_sensor name-matching is case-insensitive (`strings.ToLower`), so `Project version` still matches `"project version"` — no change needed there for the new firmware.
- The panel emits a `log` event type (its own Home Assistant connection complaints) — safely ignored by the exporter; don't chase those lines.
- New-firmware reference payload (ESPHome 2026.10.0): `{"id":"binary_sensor/Frontdoor","domain":"binary_sensor","name":"Frontdoor","icon":"","entity_category":0,"value":false,"state":"OFF"}` — `id` uses the same `domain/Name` slash format as the old `name_id`, so label values and the dashboard's `name_id=~"binary_sensor/Backdoor|binary_sensor/Frontdoor"` regex survive a fixed exporter unchanged.
