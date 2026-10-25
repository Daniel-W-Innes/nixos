# Konnected exporter outage — upstream SSE schema drift — 2026-10-25

- **Systems affected:** `prometheus-konnected-exporter` on melon (entity-state metrics, InfluxDB `konnected` bucket, Gotify door alerts); the "security" Grafana dashboard (uid `adv5bl8`)
- **Impact:** door/zone state dead for ~52 days. `konnected_entity_state_timestamp` frozen 2026-09-03, then absent entirely from 2026-09-12; zero InfluxDB writes after 2026-09-03 00:51:15Z; no Gotify door-open notifications; the dashboard's door panels (Influx) and entity panel (Prometheus) empty. No data loss of historical state — the Influx bucket (infinite retention) still holds everything through 2026-09-03.
- **Onset:** 2026-09-03 07:43:33 EDT (panel reboot; first `unknown event type: ""` in exporter history)
- **Recovery:** fix applied to the working tree 2026-10-25 (uncommitted, per repo convention); melon build passes; **pending deploy** (`sudo nixos-rebuild switch --flake .` on melon)
- **Status:** resolved in code, pending deploy
- **Methodology:** five parallel lanes (Journal/Loki, Prometheus, InfluxDB, config/state, local SSH state) + one independent verification pass. All times EDT (UTC−4) unless noted.

## 1. Executive summary

The Konnected alarm panel (ESPHome, `alarm.lc.brotherwolf.ca` = 10.8.8.118) changed the schema of its `/events` SSE stream: state events now carry the entity key as `id` (`{"id":"binary_sensor/Frontdoor",...}`) instead of `name_id`. The exporter's Go code (unchanged since June) dispatches on `state.NameID`, which unmarshals to `""` under the new schema — so every `event: state` frame fails with `unknown event type: ""` at `main.go` before reaching the Prometheus entity gauges, the InfluxDB write path, or Gotify. The schema change arrived with a panel reboot on 2026-09-03 07:43 EDT; the panel today runs ESPHome 2026.10.0 (config hash `0xb47bea79`, previously 2026.7.4 / `0xbc602521`).

The outage was silent by design: `up{job="konnected"}`, `konnected_connected`, and `konnected_last_update_timestamp` are refreshed by *ping* events, which still parse fine. The exporter never exits on upstream errors (it resubscribes forever), so `Restart=on-failure` never fires, and nothing in the repo alerts or monitors this feed. The first signal was a human noticing a stale dashboard.

Fix: prefer `state.ID` with `state.NameID` as fallback in the event dispatch, key `LastState` on the resolved ID, and accept `sensor/Uptime` case-insensitively. Source-only change; `vendorHash` unaffected. On deploy the initial state snapshot repopulates entity metrics, Influx points, and info labels within a minute — no door event required.

## 2. Timeline

All times EDT (UTC−4), 2026. Sources: Loki (journald), Prometheus, InfluxDB (via Grafana Flux), live SSH state.

| Time | Event | Source |
|------|-------|--------|
| 2026-06-04/05 | Exporter created against the then-current `name_id` schema; blocking Influx write added | git |
| 2026-08-31 08:06–08:08 | Panel reboot; firmware 2026.7.3 → 2026.7.4 — **parsing still works after this one** | Loki, Prometheus |
| 2026-09-01 22:04:07 | Last Frontdoor state change ever recorded (last Influx point for the measurement) | Influx |
| 2026-09-02 20:50:52 | Last Backdoor state change; final Influx write burst 20:51:00–20:51:15 (write counter 991 → 997, then flat) | Influx, Prometheus |
| **2026-09-03 07:43:32–33** | **Panel reboot (`connection reset by peer`). First `unknown event type: ""` ever — 22 in the first second (full state snapshot), then ~1/min continuously** | Loki |
| 2026-09-03 07:44:00 | Panel uptime 257,732 → 52 s (reboot with the schema-changing firmware/config) | Prometheus |
| 2026-09-03 07:44:12 | First `konnected_scrape_ok=0` in Prometheus history (hourly minima had been 1 since Aug 26) | Prometheus |
| 2026-09-11 20:51–20:56 | Exporter restart (melon switch) clears the in-memory `LastState` map → `konnected_entity_state_timestamp` series hard-disappear (last sample 20:43:15); info labels (`device_id`, `esphome_version`, …) go empty | journal, Prometheus |
| 2026-09-11 20:53:42 | influxd restarts; the `/api/v2/write` counter series vanishes from its metrics (old process died holding 997) | Prometheus |
| 2026-09-22, 25, 27 | Further clean exporter deactivations (switches) — no crashes, `NRestarts=0` throughout | journal |
| 2026-10-08 21:40–41 | Current exporter + influxd start (melon reboot); **zero** `/api/v2/write` requests since | systemd, Influx metrics |
| 2026-10-23 22:49:58 | Panel reboot #2 — now ESPHome 2026.10.0; parse errors continue (they predate this reboot) | journal |
| 2026-10-25 14:30–15:00 | Investigation (5 lanes); root cause verified against live SSE, code, journal, and metrics; fix applied to working tree; melon build passes | session |

## 3. Root causes and fixes

| # | Root cause | Fix | Where |
|---|-----------|-----|-------|
| 1 | Panel firmware/config changed the `/events` SSE payload: `name_id` → `id`. Exporter dispatch reads only `NameID` → every state event dies with `unknown event type: ""` before Prometheus/Influx/Gotify | Prefer `state.ID` with `state.NameID` fallback in `refresh()`; key `LastState` on the resolved entity ID; accept `sensor/Uptime` case-insensitively | `modules/konnected-exporter/main.go` (working tree, uncommitted; melon build passed) |
| 2 | Failure mode is silent by design: `up`/`connected`/`last_update_timestamp` are ping-driven; exporter never exits on upstream errors; no alert or uptime-kuma monitor exists for this feed | Not fixed here; optional hardening — an alert on `konnected_scrape_ok == 0` (or entity-timestamp staleness) would have caught this within minutes. Decoder doc added so future sessions recognize the class | follow-up |

### Evidence for the payload change

Live capture of `http://alarm.lc.brotherwolf.ca/events` (2026-10-25, 75 s: 59 state + 8 ping + 4 log events, **0** occurrences of `name_id`):

```
event: state
data: {"id":"binary_sensor/Frontdoor","domain":"binary_sensor","name":"Frontdoor","icon":"","entity_category":0,"value":false,"state":"OFF"}
```

- Code path: `main.go` `State.NameID json:"name_id"` → `refresh()` `parts := strings.Split(state.NameID, "/")` → `default: return fmt.Errorf("unknown event type: %q", parts[0])` — with `name_id` absent, `parts[0]` is `""`, matching the journal error verbatim.
- InfluxDB side proves the write path was never reached: the bucket (`konnected`, `retentionPeriod=0`) is intact and readable through Grafana; last points Frontdoor `2026-09-02T02:04:07Z` / Backdoor `2026-09-03T00:50:52Z`; the write counter went flat at 997 after 00:51:15Z; zero `/api/v2/write` series in the current influxd process; zero 4XX ever — writes stopped, they did not fail.
- Everything else is green: `up{job="konnected"}=1`, `connected=1`, `last_update_timestamp` advancing every 10 s (pings), influxdb2 health `pass`, SSE connection ESTAB, panel ARP REACHABLE.

## 4. Follow-ups

- `docs/debug/schema-drift.md` decoder added for this symptom class (green liveness + frozen data + `unknown event type` = upstream payload drift); `docs/debug.md` topic table updated; `docs/issues/15-konnected-schema-drift.md` + planned-fixes entry created.
- **Deploy and verify** (user): commit/push, then on melon `sudo nixos-rebuild switch --flake .`; verify `curl -s localhost:9877/metrics | grep konnected_entity_state_timestamp` shows `binary_sensor/Frontdoor`/`Backdoor` with fresh ms timestamps, the journal errors stop, and the dashboard repopulates within a minute.
- Optional hardening: Grafana alert on `konnected_scrape_ok == 0` (mind the `== bool 0` equality gotcha in `docs/debug/prometheus.md`) or on `time() - konnected_last_update_timestamp` staleness; `/healthz` also ignores the SSE connection.
- Side observations (not causal): melon load average ~26 with 10 Gi swap in use; the panel's own log shows its Home Assistant integration broken (`Home Assistant 2025.4.2 (10.8.8.130): Reading failed CONNECTION_CLOSED`); Grafana's known SQLite-lock 503s were active during the investigation.
