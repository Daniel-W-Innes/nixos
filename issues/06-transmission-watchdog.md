# Transmission watchdog to auto-recover from tunnel wedges

### Problem

2026-09-03: transmission's single-threaded session blocked on an operation through the dead Proton tunnel, which froze the RPC server too (21:35–21:56 EDT). The daemon didn't crash, so `Restart=on-failure` can't help, and Uptime-Kuma detected it but nothing acted. Recovery was pure luck (tunnel returned, blocked call completed).

### Fix

Add a systemd timer (e.g. every 1 min) running a small script that:

1. GETs `http://localhost:9091/transmission/rpc` with the RPC credentials (reuse `transmission.credentialsFile.age` via `LoadCredential`, same pattern as the transmission service and lidarr-mcp), with a short timeout (~10 s).
2. On failure, increments a state file; after N consecutive failures (e.g. 5), `systemctl restart transmission`.

Restarting while the tunnel is dead re-blocks the new process, but once the tunnel returns the restarted daemon recovers immediately instead of waiting for the in-flight operation to unwind. (Alternatively: restart immediately on first failure — since the failure mode is a hang, not a crash, there's no downside beyond a brief RPC blip.)

### Verification

- Manual test: `systemctl stop` the port-mapping/wedge transmission artificially, watch the timer restart it.
- Or observe the next Proton rotation: outage duration should be ~1 min instead of ~20 min.

### References

- 2026-09-03 incident report; `generic/server/arr.nix` (transmission service def); `docs/lidarr-mcp.md` (LoadCredential pattern)
