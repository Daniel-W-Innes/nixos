# openweathermap rain metric carries forward stale values when OWM omits `rain`

### Problem

`openweathermap_current_rain_depth_meters` (job="openweathermap", instance="localhost:9876", melon) freezes at the last observed rain depth for hours to days during dry weather, while temperature from the same exporter stays fresh and correct. Confirmed plateaus: `0.00015` for ~88 h (2026-08-13 05:00Z → 08-16 21:00Z, verified `changes(rain[2d])` = 0 across 17,280 consecutive 10 s scrapes), `0.00017` for ≥65 h (08-17 → 08-19), `0.00027` for 72 h (10-09 → 10-12) and again from 2026-10-14 13:00Z. 90 d stats: median 0.15 mm/h, 85.9% of hours ≥ 0.1 mm/h — impossible for Ottawa; any hourly wet/dry binarization (forecast confusion matrices, RMSE panels) is dominated by the artifact.

Root cause: `main.go` `refresh()` calls briandowns/openweathermap v0.21.1 `OneCallByCoordinates`, which does `json.NewDecoder(resp.Body).Decode(&w)` — decoding **in place into the receiver struct**. OWM omits `rain` (also `snow`, `wind_gust`) from `current` when no precipitation is falling, and Go's `encoding/json` leaves absent keys untouched, so `Current.Rain.OneH` keeps its previous value and is re-emitted at every scrape (10 s) across every refresh (2 m). The metric effectively reads "rain depth at the most recent poll where OWM reported rain" — a sticky max. Same bug class silently affects `current_snow_depth_meters` and `current_wind_gust_meters_per_second`.

Ruled out: exporter down (up=1, 360/360 scrapes per hour), failed refreshes serving cache (attempt≈success to within −76 ms; on failure the exporter emits no current metrics at all, so temperature would go stale too), wrong JSON field (Collect reads `Current.Rain.OneH`, not daily/hourly), and series gaps (samples continuously present). History is unrecoverable — including the genuinely-dry frozen-0 runs (e.g. Sep 19–26) that are indistinguishable from stuck values.

### Fix

Reset `Current` before each refresh so omitted fields emit 0:

```go
e.client.Current = owm.OneCallCurrentData{}
```

Applied in the working tree 2026-10-16 (uncommitted — `modules/openweathermap-exporter/main.go`, `refresh()`). Source-only change; the pinned `vendorHash` in `modules/openweathermap-exporter.nix` is unaffected. `go build ./...` passes.

### Verification

After deploy (`nixos-rebuild switch --flake .#melon`; the unit restarts with the new binary):

- Dry hours read exactly 0: `openweathermap_current_rain_depth_meters` returns to 0 between rain events instead of plateauing.
- `changes(openweathermap_current_rain_depth_meters[7d])` tracks actual rain events.
- Prometheus: rain/snow/wind_gust series present and updating at the same cadence as temperature.

### References

- `modules/openweathermap-exporter/main.go:143` (emits `Current.Rain.OneH/1000.0`)
- briandowns/openweathermap v0.21.1: `onecall.go:190` (in-place `Decode(&w)`), `history.go:34` (`Rain` struct), `onecall.go:62` (`OneCallCurrentData`)
- `docs/debug/known-noise.md` — metar-exporter is the only other precipitation source on the infra and is broken, so this metric is the sole rain signal
