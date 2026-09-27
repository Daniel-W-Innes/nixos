# Postgres unclean shutdown every stop — podman stop's 10s default SIGKILLs postgres

**Open.** Opened 2026-09-27. Fix committed (`07e5f95`) and deployed 2026-09-27; verification pending.

### Problem

`podman stop` (the oci-containers module's ExecStop) has a default 10 s SIGTERM→SIGKILL timeout. Postgres 16 fast shutdown takes ~16 s under load — the 2026-09-27 10:03:54 stop shows the exact shape: `received fast shutdown request` at 10:03:54, a running statement cancelled, container killed before `database system is shut down` could ever be logged. So **every reboot** SIGKILLed postgres mid-shutdown, and the next start logged `database system was not properly shut down; automatic recovery in progress` (10:15:40). WAL replay makes this safe in practice, but repeated unclean stops risk torn pages / lost fsyncs and mask real corruption.

Second killer, same fix: the boot-storm kill of the first container attempt (`f2b9600c`, SIGKILL at 10:11:11 during podman's boltdb `database is locked` error-cleanup path — conmon's exit-file ENOENT shows podman's cleanup racing conmon). Whatever the exact killer, both paths now get the 90 s grace.

### Fix

`generic/server/forgejo.nix`: `extraOptions = [ "--stop-timeout=90" ]` on the `forgejo-db` container. `podman stop` (without `-t`) then waits up to 90 s before SIGKILL — in both the normal ExecStop path and podman's internal error-cleanup path. 90 s keeps the whole stop inside the unit's `TimeoutStopSec=120` (module default, plain value — overriding it would conflict with the module's definition).

The same one-liner is applied to the other DB containers too (2026-09-27): `uptime-kuma-mariadb` (`generic/server/uptime.nix`) and `bookorbit-db` pgvector (`modules/bookorbit.nix`, appended to its existing `extraOptions`). Any container whose process needs >10 s to shut down should get it.

### Verification plan

- After deploy: `systemctl stop podman-forgejo-db.service` under load and confirm postgres logs `database system is shut down` (no 137/SIGKILL).
- Next boot: confirm no `database system was not properly shut down` on the DB's first start.
- CI builds the melon toplevel on push.

### References

- `docs/reports/2026-09-27-forgejo-dependency-outage.md` §4.2, §7.4
- `docs/debug/forgejo.md`
