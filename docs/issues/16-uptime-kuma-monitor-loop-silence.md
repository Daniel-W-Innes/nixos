# uptime-kuma monitor loop goes silent while monitors are failing

**Open.** Opened 2026-11-03. Recovered by `systemctl restart uptime-kuma` (21:43 EST); mechanism unknown. Watch for recurrence.

### Problem

During the 2026-11-03 KVM-pause incident, uptime-kuma's monitor scheduler stopped emitting `[MONITOR]` lines while monitors were still failing — twice: a ~20 min gap (21:03 → 21:23 EST), then permanent silence from 21:24:45 EST until the restart at 21:43:34. The second silence began ~70 s after `systemctl restart proton.service` (the VPN namespace rebuild).

State during the silence:

- 11 threads `S (sleeping)`, `wchan=0` — nothing blocked in the kernel
- HTTP responsive (302 in 10 ms) and dashboard socket/auth working — the event loop was alive
- mariadb answering on 127.0.0.1:3306 (its own published port intact) — not a DB outage
- Every monitor target verified healthy at the time (transmission loaded, bookorbit 200, grafana `/api/health` 200)

A fresh process (restart at 21:43) booted cleanly, connected to the DB, and all monitors went green immediately — so nothing in the DB state or configuration was wrong.

### What was ruled out

- podman nat flush by the proton down-script — it deletes only its own chains; 23155/3306 published ports verified working after the restart
- DB wedge — mariadb answering throughout; fresh process connected instantly
- Crash/OOM/restart loop — `NRestarts=0`, 394 MB RSS, no exit
- Target-side failure masking logs — uptime-kuma logs a Failing line *every* check while down (60 s cadence observed 20:55–21:02); silence with red monitors is itself the anomaly

### Hypotheses (untested)

- A monitor fetch hung past its configured timeout in a way that wedged the check scheduler (the transmission monitor's "timeout of 48000ms exceeded" phase, or a traefik connection through the namespace that never completed)
- A synchronous mariadb query blocking the node event loop intermittently (mysql2 sync path during a pool stall)

### Recovery

`sudo systemctl restart uptime-kuma` — the only known fix. It is safe: monitor state lives in mariadb, and the process restarts in ~3 s.

### Watch for

- Recurrence signature: red monitors on the dashboard + **zero** `[MONITOR]` journal lines for >5 min (`journalctl -u uptime-kuma | grep MONITOR`). Green dashboard + no MONITOR lines is **normal** (successful checks don't log) — do not confuse the two.
- If it recurs: before restarting, capture `strace -p <MainPID> -f -tt -e trace=network,futex,epoll_wait` for ~60 s and the per-thread `/proc/<pid>/task/*/wchan`, then restart. Compare the hung check's target against the last MONITOR line to identify which monitor triggered it.

### References

- `docs/reports/2026-11-03-kvm-pause-dependency-cancel.md`
- `generic/server/uptime.nix` (uptime-kuma + mariadb container definition)
