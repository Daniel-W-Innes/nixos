# KVM-Pause Dependency-Cancel Storm — Post-Incident Report — melon, 2026-11-03

- **Systems affected:** forgejo, uptime-kuma, audiomuse (flask + 2 workers), bookorbit, gitea-runner-melon, transmission (start wedge + namespace breakage), traefik→transmission backend; onion separately lost ~20 units to an interrupted `nixos-rebuild test`
- **Impact:** 5 h host-level freeze (15:01:36 → 20:01:36 EST), then a dependency-cancel storm on resume; services down from resume until manually started (20:47–21:43 EST); **no data loss**
- **Onset:** 15:01:36 EST 2026-11-03 — host-side KVM pause (guest monotonic clock frozen; kvm-clock jumped the wall clock forward on resume)
- **Recovery:** `/tmp/melon-recover.sh` (20:47 EST), `systemctl restart mnt-media.mount` + transmission restart, `systemctl restart proton.service` (21:23 EST), `systemctl restart uptime-kuma` (21:43 EST); all uptime-kuma monitors green
- **Status:** resolved; upholds-direction fix applied as **uncommitted diffs** (`generic/server/forgejo.nix`, `generic/server/audiomuse.nix`, `generic/server/uptime.nix`, `modules/bookorbit.nix`); onion still needs `sudo nixos-rebuild switch --flake .#onion`
- **Methodology:** infra-debug skill — 4 parallel lanes (journal/Loki, Prometheus, repo config, live SSH) plus one verification pass; recovery via user-run scripts in `/tmp` on melon. All times EST (UTC−5).

## 1. Executive summary

A host-side hypervisor pause froze melon's vCPUs for 5 h (15:01:36 → 20:01:36 EST). On resume, podman's boltdb was mid-transaction — the `database is locked` error (exit 125) killed several DB containers, whose failure cancelled their consumers' start jobs (`result 'dependency'`). systemd never re-queues a dependency-cancelled job, and the 2026-09-27 `upholds=` fix that was supposed to cover exactly this case was **inverted**: it was placed on the consumer units, where it upholds the DB from the app (the wrong direction) and does nothing for the outage.

A second, independent wave followed: `proton.service` had frozen mid-setup during the pause and "finished" post-resume with an incomplete ruleset — the main-ns route to the VPN namespace was missing, so traefik hung on transmission backend connections while the LAN path kept working. Transmission also wedged on start (stale CIFS session after the 5 h freeze — the 2026-09-18 class), and uptime-kuma's monitor loop went silent (mechanism unknown; restart recovered it).

Every service recovered with no data loss. The config fix for the dependency-cancel class is correct this time (upholds on the DB unit), awaiting review and deploy.

## 2. Timeline

All times EST (UTC−5), 2026-11-03. Sources: journal (systemd + uptime-kuma MONITOR lines), Prometheus, live SSH state, the recovery scripts' outputs.

| Time | Event | Source |
|------|-------|--------|
| ~14:31 | `nixos-rebuild switch` on melon (post daily flake update) | systemd |
| ~15:00:48 | melon reboots. Its clock is **4:56 fast** at boot (btime stamped 00:56:48Z = fast-clock value; `last`/`uptime` show 14:59 real) | journal, `last reboot` |
| ~15:01:30 | timesyncd steps the clock back 4:56 — all later stamps are real time | journal gap |
| 15:01:36 | **Host-side KVM pause begins.** Guest monotonic time freezes (proven by `/proc/uptime`); wall clock frozen with it | `/proc/uptime` |
| 15:01:49 | `proton.service` Starts — frozen mid-setup ~1 s later, for the whole pause | systemd |
| 20:01:36 | **Resume.** kvm-clock jumps the wall clock forward to host time (20:01:57: proton's up-script "Finished" — 21 s of post-resume work, 5 h of wall) | systemd |
| 20:01:36–20:09 | Resume storm: podman boltdb `database is locked` (exit 125) → DB containers fail → consumers' start jobs cancelled with `result 'dependency'`: forgejo, uptime-kuma, `podman-audiomuse-flask`, `podman-audiomuse-worker-1/2`, `podman-bookorbit-app`; melon's gitea-runner crash-loops and burns its start-limit | journal |
| 20:01:36+ | CIFS session to pumpkin goes stale during the freeze → transmission start wedges in `[cifs] wait_for_response` (2026-09-18 class) | `/proc/<pid>/task/*/stack` |
| ~20:47 | **melon-recover.sh** (user-run): starts all dependency-cancelled units; `reset-failed` + start for the runner; transmission restart hangs (the CIFS wedge) | /tmp/melon-recover.sh |
| ~20:50 | `systemctl restart mnt-media.mount` + fresh transmission start → session loads (~9–10 min, tight against `TimeoutStartSec=600`) | systemd |
| 20:55:43–21:02:45 | uptime-kuma logs every 60 s: Bookorbit 502 (app's ~5 min startup: migrations/seeding), **Transmission "timeout of 48000ms exceeded"** (traefik hanging on the missing route to 192.168.15.0/24), Grafana 503 → Pending (self-recovers) | uptime-kuma |
| 21:00:52+ | Transmission monitor flips to fast 502s (traefik → refused while the daemon isn't listening) | uptime-kuma |
| ~21:03–21:23 | First monitor-log silence (mechanism unknown — see issue 16) | uptime-kuma |
| 21:23:32 | **fix2**: `systemctl restart proton.service` — clean run (active/exited 0); namespace + route rebuilt; transmission restarts with the namespace and reloads its session (~12 min, done ~21:35) | /tmp/melon-fix2.out |
| ~21:24:45 | uptime-kuma monitor loop goes silent for good (11 threads sleeping, HTTP responsive, DB answering; all targets healthy) | journal, /proc |
| 21:43:34 | **fix3**: `systemctl restart uptime-kuma` — clean boot, all monitors green | /tmp/melon-fix3.out |

Onion, second incident (found mid-investigation): an interrupted `nixos-rebuild test` at 19:22 EST left ~20 units inactive **with 0 failed** — invisible to `--failed` — including mcp-grafana, alloy, node-exporter, lidarr-mcp, gitea-runner-onion. Pending: `sudo nixos-rebuild switch --flake .#onion`.

## 3. Scope of impact

**Broken (all recovered):**

- forgejo + CI runners — dependency-cancelled at resume; down 20:01 → ~20:48 EST
- uptime-kuma — dependency-cancelled at resume; down 20:01 → ~20:47 EST (its mariadb container was never affected)
- audiomuse (flask + workers) — dependency-cancelled at resume; down 20:01 → ~20:47 EST
- bookorbit — dependency-cancelled at resume; app then took ~5 min to boot (migrations/seeding); HTTP 200 verified via published port and traefik
- transmission — CIFS start wedge after resume, then namespace breakage; fully healthy after fix2 (~21:35 EST): LAN 403, namespace-IP 409, traefik route 301
- Grafana — transient 503 through traefik post-resume; self-recovered (`/api/health` 200)
- onion — ~20 inactive units from the interrupted test rebuild (not yet fixed; pending switch)

**Unaffected:**

- Data: postgres/mariadb data dirs intact; podman's boltdb recovered; no corruption found
- melon's podman published-port rules — intact through the proton restart (the module's down-script deletes only its own chains; verified: 23155 loopback+LAN 200, 3306 answering)
- The LAN path to transmission throughout the post-fix2 window

## 4. Key evidence

### 4.1 The dependency-cancel chain (same triplet as 2026-09-27)

The melon-recover.sh unit list is the record of what was cancelled: forgejo, uptime-kuma, `podman-audiomuse-flask`, `podman-audiomuse-worker-1/2`, `podman-bookorbit-app`, plus melon's gitea-runner (crash-loop, `start-limit-hit` → `reset-failed` required). All were started manually and stayed up — nothing re-queued them, exactly the 09-27 mechanism (`docs/reports/2026-09-27-forgejo-dependency-outage.md`), this time triggered by boltdb `database is locked` on resume from a host pause rather than a boot storm.

### 4.2 The inverted upholds fix

The 09-27 fix put `upholds = [ "podman-forgejo-db.service" ]` **on forgejo** — "while forgejo is up, keep the DB running". The correct placement is on the DB unit: `upholds = [ "forgejo.service" ]` — "while the DB runs, keep forgejo running". When the DB recovers via its own `Restart=`, systemd then re-queues the consumer. The same inversion existed in `uptime.nix`, `audiomuse.nix`, and `modules/bookorbit.nix`; all four are fixed as uncommitted diffs.

### 4.3 The frozen proton.service (frozen-boot namespace signature)

- `systemctl show proton.service`: Started 15:01:49, "Finished" 20:01:57 — 5 h of wall for ~21 s of work; the up-script completed post-resume with an incomplete ruleset
- Consequence: traefik → `192.168.15.1:9091` hung (uptime-kuma's 48 s timeouts), while onion → LAN `10.8.8.140:9091` returned 403 (the DNAT rules existed; the route didn't)
- Post-fix2 verification from melon: `192.168.15.1:9091` → HTTP 409 (route OK, daemon answering); localhost:9091 and self-LAN:9091 still refused — **expected** (see 4.4)

### 4.4 No localhost port mapping exists — and never did

VPN-Confinement (pinned rev `cc37bcf`) `portMappings` generate **only** a PREROUTING DNAT chain (`-t nat -N proton-prerouting`, `-t nat -A PREROUTING -j proton-prerouting`) plus INPUT rules on the veth; `accessibleFrom` only installs routes via the bridge; the down-script deletes only its own chains (no `-F`). Locally-generated traffic (localhost, self-LAN) never traverses PREROUTING — so connection-refused on `localhost:9091` from melon is normal, not a symptom. `docs/debug/transmission.md` previously claimed a localhost mapping existed; corrected.

### 4.5 uptime-kuma monitor-log decay

```
21:02:45 [MONITOR] WARN: Monitor #30 'Arr': Failing: Child monitors down: Transmission …
         ~20 min of silence while transmission was still failing
21:23:35 [MONITOR] WARN: Monitor #5 'Transmission': Pending: Request failed with status code 502 | Retry: 1
21:24:35 [MONITOR] WARN: Monitor #5 'Transmission': Pending: Request failed with status code 502 | Retry: 2
21:24:45 [MONITOR] WARN: Monitor #30 'Arr': Pending: Pending child monitors: Transmission
         silence — permanently, until the 21:43 restart
```

During the final silence: 11 threads `S (sleeping)`, wchan=0, HTTP responsive (302 in 10 ms), mariadb answering on 3306, every monitor target healthy. A fresh process restarted clean and went green — the wedge was process state, not configuration. Mechanism unknown: `docs/issues/16-uptime-kuma-monitor-loop-silence.md`.

### 4.6 Clock reconciliation

btime 00:56:48Z is the **fast-clock** stamp of a boot that happened at 15:00:48 EST real (offset 4:56; timesyncd stepped it back ~15:01:30). All pre-step stamps need −4:56; post-step stamps are real. This matches the earlier incident reports' convention: anchor to MESSAGE timestamps, not `now`.

## 5. Ruled out

| Hypothesis | Killing evidence |
|---|---|
| Boot-time podman contention storm (09-27 class) | The failures came at **20:01–20:09**, 5 h after the 15:00 boot — boltdb locked mid-transaction by the pause/resume, not a boot storm |
| DB data corruption | All DB containers started clean from existing data dirs; forgejo migrate ran clean; bookorbit migrations/seeding completed |
| Bookorbit port mapping missing | I checked `iptables -t nat` and saw nothing; podman 5.8.9's netavark installs DNAT in **nftables** (`tcp dport 23155 dnat ip to 10.89.0.5:3000`) — the mapping was there all along; the 502s were the app's ~5 min startup |
| localhost:9091 mapping "lost" in the reboot | Never existed (§4.4) — the module is PREROUTING-only at this rev |
| fix2's proton restart flushed podman's nat rules | The down-script deletes only `proton-prerouting`/`proton-postrouting` chains; verified post-fix2: 23155 answers on loopback *and* LAN, 3306 answers |
| uptime-kuma wedged on its DB | mariadb answering on 3306 during the silence; fresh process connected instantly at 21:43:41 |
| uptime-kuma crash / OOM | No restart (NRestarts=0), 394 MB RSS, HTTP responsive throughout |
| Grafana broken (original complaint) | active + `/api/health` 200; the 20:56 503 was transient post-resume |
| DNS broken for monitor URLs | `transmission.lc.brotherwolf.ca` resolves; monitors green after restart |

## 6. Root cause

1. **Host-side KVM pause** froze melon for 5 h (15:01:36 → 20:01:36 EST). Guest-invisible except by monotonic-time forensics; the provider-level reason is an open question for the host owner.
2. On resume, podman's boltdb was mid-transaction (`database is locked`, exit 125) → DB container units failed.
3. `Requires=` cancelled the consumers' start jobs (`result 'dependency'`), which systemd never re-queues; the 09-27 `upholds=` fix was on the wrong unit (inverted direction), so nothing self-healed.
4. Second wave: `proton.service` completed post-resume with an incomplete ruleset (missing main-ns route to the namespace) → traefik hung on the transmission backend; and the 5 h freeze staled the pumpkin CIFS session → transmission's start wedge (2026-09-18 class).
5. uptime-kuma's monitor loop went silent during the failing window and never resumed; mechanism unknown, restart recovered it.

## 7. Fix and follow-ups

1. **Upholds direction (uncommitted diffs — review + deploy with the next switch):** `upholds` moved to the DB units in `generic/server/forgejo.nix` (`podman-forgejo-db` → `forgejo.service`), `generic/server/uptime.nix` (`podman-uptime-kuma-mariadb` → `uptime-kuma.service`), `generic/server/audiomuse.nix` (`podman-audiomuse-postgres` → flask + worker units), `modules/bookorbit.nix` (`podman-bookorbit-db` → `podman-bookorbit-app`).
2. **Onion switch pending:** `sudo nixos-rebuild switch --flake .#onion` — restores mcp-grafana, alloy, node-exporter, lidarr-mcp, gitea-runner-onion and the other ~15 inactive units from the interrupted 19:22 test rebuild.
3. **Host-pause question:** ask the VPS provider why melon was paused 5 h (or check host-side logs if self-hosted KVM). Nothing in-guest can prevent or detect this except post-hoc monotonic forensics; consider an external watchdog (uptime-kuma on another host probing melon's exporters would have shown a 5 h flatline — worth checking whether it did).
4. **transmission `TimeoutStartSec=600` vs ~9–10 min load** is tight (both this incident and 09-18) — consider raising it, or moving session stats off CIFS.
5. **uptime-kuma monitor-loop silence** — open issue: `docs/issues/16-uptime-kuma-monitor-loop-silence.md`. If it recurs, capture with `strace -p` during the silence before restarting.
6. **Docs updated:** `docs/debug/forgejo.md` (inverted-upholds decoder), `docs/debug/transmission.md` (localhost claim corrected; frozen-boot namespace signature), `docs/debug.md` (EDT→EST anchor line).

## References

- `docs/reports/2026-09-27-forgejo-dependency-outage.md` (same dependency-cancel class, boot-storm trigger)
- `docs/reports/2026-09-18-transmission-wedge.md` (CIFS start-wedge class)
- `docs/issues/done/10-forgejo-dependency-fail-after-reboot.md`, `docs/issues/16-uptime-kuma-monitor-loop-silence.md`
- `docs/debug/forgejo.md`, `docs/debug/transmission.md`
- Evidence: `/tmp/melon-recover.sh`, `/tmp/melon-fix2.out`, `/tmp/melon-fix3.out` on melon; uptime-kuma journal `|= "MONITOR"`; VPN-Confinement module source at rev `cc37bcf` (`modules/vpn-up.nix`, `vpn-down.nix`, `firewall-utils.nix`)
