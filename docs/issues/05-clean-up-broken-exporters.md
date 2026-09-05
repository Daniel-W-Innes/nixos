# Clean up broken/noisy exporters drowning real signals

### Problem

Several exporters have been broken for weeks and emit constant error noise into the journal and `up=0` series into Prometheus. During the 2026-09-03 transmission investigation, two of them (metar, statuspage) actively misled the diagnosis — the metar exporter's `EAI_AGAIN` DNS errors looked like a smoking-gun network outage but are constant background noise (8 lines/10 min, all day). Verified broken as of 2026-09-04:

| Exporter | Symptom |
|---|---|
| `statuspage-exporter` (podman, :9747) | "context deadline exceeded" on every fetch, ~every 10 s, all day; up=0 |
| `metar-exporter` (podman, :9750) | `socket.gaierror: [Errno -3] Try again` on every poll — DNS broken inside the container |
| `unpoller` (:radish) | 401 Unauthorized + nil-pointer panics on every scrape |
| `shelly` (:9882) | 401 Unauthorized every scrape |
| `copyparty` (pumpkin:30266) | up=0 constantly |

### Fix

For each: either fix the underlying config (tokens/API keys/URLs, or container DNS for metar) or **remove the exporter and its scrape job**. Deleting is the honest option where the feature isn't used. Every removed noisy unit is one less red herring and a smaller journal for Loki queries to scan.

### Verification

- Journal: no recurring errors from the fixed/removed units over 24 h.
- Prometheus: `up` = 1 for kept exporters; dead scrape jobs removed from `up` entirely.

### References

- `docs/debug.md` §"Known noise"
