# konnected exporter rejects all state events after panel firmware changed SSE payload `name_id` → `id`

**DONE 2026-10-25.** Fix deployed to melon with the 2026-10-25 switch (binary `konnected-exporter-0.5.7`) and verified the same evening: entity metrics and info labels repopulated within a minute of the unit restart, Influx writes resumed (25× 204 vs one transient 500 on the first write), and a real Backdoor open/close at 21:02 EDT was captured end-to-end including the Gotify notification. One residual: Zone 5's initial snapshot point was the dropped write, so it is absent from `konnected_entity_state_timestamp` until its next state change.

### Problem

`prometheus-konnected-exporter` on melon broke at a panel reboot on 2026-09-03 07:43:33 EDT and went unnoticed for ~52 days. The Konnected panel (ESPHome, now 2026.10.0) changed its `/events` SSE payload: state events carry the entity key as `id` (`{"id":"binary_sensor/Frontdoor",...}`) instead of `name_id`. The exporter dispatches on `state.NameID` only (`main.go` `refresh()`), so every state event fails with `unknown event type: ""` before reaching the Prometheus entity gauges, the InfluxDB write path (blocking, no retry), or Gotify.

Signature, precisely because the failure is silent:

- `up{job="konnected"}=1`, `konnected_connected=1`, `konnected_last_update_timestamp` advancing — all refreshed by *ping* events, which still parse
- `konnected_scrape_ok` dips to 0 for ~10 s once a minute (each failing state batch), 6 h averages ≈ 0.833
- `konnected_entity_state_timestamp` frozen at last values, then **absent entirely** after the 2026-09-11 20:51 EDT exporter restart cleared the in-memory `LastState` map
- info labels (`device_id`, `esphome_version`, `ip_address`, `projest_version`) empty for the same reason (text_sensor events never parsed)
- journal: `Error processing event: unknown event type: ""` ~1/min continuously since onset
- InfluxDB bucket `konnected`: last points Frontdoor 2026-09-02T02:04:07Z / Backdoor 2026-09-03T00:50:52Z; zero writes since (write counter flat at 997 after 00:51:15Z, then series gone after influxd restart); zero 4XX — writes stopped, they did not fail
- the exporter never exits on upstream errors (infinite resubscribe loop), so `Restart=on-failure` never fires and no alert/monitor exists for this feed anywhere in the repo

Onset evidence (Loki): 0 `unknown event type` errors before 2026-09-03 11:00Z, 38 in the 11:00–12:00Z hour (22 in the first second — the panel's full state snapshot at connect), then 60/h steady. The panel rebooted 2026-09-03 11:43:32Z (`connection reset by peer`, uptime 257,732 → 52 s). Full write-up: `docs/reports/2026-10-25-konnected-schema-drift.md`.

Ruled out: exporter crash/restart loop (`NRestarts=0`, clean stops only), InfluxDB down/bucket lost/retention/auth (health pass, bucket readable through Grafana, no write *attempts*), network to panel (ESTAB, SSE flowing), entity rename (live IDs match the dashboard regex exactly), Grafana datasource drift (Flux reads return 200), config drift in repo (no konnected/influx commits since 2026-06-28).

### Fix

Apply the same change to `modules/konnected-exporter/main.go`:

```go
// Newer ESPHome firmwares send the entity key as `id` instead of `name_id`.
entityID := state.ID
if entityID == "" {
    entityID = state.NameID
}
parts := strings.Split(entityID, "/")
```

plus: pass `entityID` into `binary_sensor`/`light`/`sensor` and key `LastState` on it (instead of `binaryState.NameID`/`lightState.NameID`); replace the `sensor` uptime check with `strings.EqualFold(entityID, "sensor/uptime") || entityID == "sensor.uptime"`. No other handler changes needed — the per-domain payload shapes (`value`, `state`, `effect`, `color_mode`, `uom`) and the text_sensor names (`Device ID`, `ESPHome Version`, `Ethernet IP Address`, `Project version`) still match the existing structs and switch cases.

Status: deployed and verified 2026-10-25. Source-only change; the pinned `vendorHash` in `modules/konnected-exporter.nix` is unaffected. `nix build .#nixosConfigurations.melon.config.system.build.toplevel` passes.

### Verification

Verified 2026-10-25, ~6 h after the 15:25:54 EDT deploy:

- ✓ `curl -s localhost:9877/metrics | grep konnected_entity_state_timestamp` — `binary_sensor/Frontdoor` and `binary_sensor/Backdoor` (both `false`) plus zones/lights with fresh ms timestamps (connect-time snapshot repopulated `LastState` within ~40 s)
- ✓ journal: `unknown event type` errors stopped at the restart; 8 lines in 6 h, the only error being the single Influx timeout below
- ✓ info labels repopulated: `esphome_version="2026.10.0 (config hash 0xb47bea79)"`, `device_id="94b555ab24b8"`, `ip_address="10.8.8.118"`
- ✓ Influx writes resumed: `http_api_requests_total{path="/api/v2/write"}` = 25× 204 + 1× 500 (transient timeout on the first write, 15:26:22 — dropped Zone 5's initial point only); Grafana Flux `last()` on the dashboard's datasource: Backdoor 21:02:24 EDT, Frontdoor 15:26:32 EDT
- ✓ `min_over_time(konnected_scrape_ok[1h])` = 1 — no more dips
- ✓ a real Backdoor open/close at 21:02 EDT produced entity-state updates, 2 Influx points, and a Gotify notification with no exporter send errors

### References

- `modules/konnected-exporter/main.go` — `State` struct (json tags for both `name_id` and `id`), `refresh()` dispatch, `Run()` resubscribe loop
- `modules/konnected-exporter.nix`, `generic/server/visibility.nix` (scrape job `konnected` → `localhost:9877`, Influx org `visibility`/bucket `konnected`, Gotify allowlist `Frontdoor,Backdoor`)
- `docs/reports/2026-10-25-konnected-schema-drift.md` — full timeline and evidence
- `docs/debug/schema-drift.md` — decoder for the symptom class (green liveness + frozen data + `unknown event type`)
