# PIA tunnel outage — endpoint rotation + blind stall alerting — 2026-11-25

**Open.** Tunnel down since 2026-11-25 10:21:41 EST; torrent traffic at ~0.04% of baseline; `pia-port-forward` failing every 15 min. Transmission RPC and the arr stack unaffected (veth-local).

### Problem

`vpn-confinement-openvpn@pia` pins `140.228.24.161:1197` (montreal429) from the `.ovpn` in `secrets/pia-vpn.age`. After 3 stable days, the tunnel hit `SIGUSR1[soft,ping-restart]` (inactivity) at 10:21:41 EST and has never reconnected — `TLS Error: TLS key negotiation failed to occur within 60 seconds` loops every ~6 min (230 TLS errors / 116 restart pauses on the day), with no `AUTH_FAILED`, i.e. the server never answers. PIA's current server list (`https://serverlist.piaservers.net/vpninfo/servers/v6`, checked 21:10 EST) contains neither `montreal429` nor the pinned IP, while a different Montreal PF server (107.182.119.118) exists → the endpoint was retired/rotated. OpenVPN's `Restart=always` cannot recover from a dead endpoint; the `remote` IP in the secret must change.

### Also

- The stall alert was blind the whole time: `openvpn-exporter` (job `openvpn`) has been `up=0` for ≥7 days, so `pia-tunnel-stalled`'s `time() - openvpn_status_update_time_seconds > 300` evaluates to NoData → `noDataState = OK`. (`openvpn-exporter-down` has been firing for the same reason — chronic.)
- Collateral while the tunnel is dead: `pia-port-forward` fails with `curl: (28)` then `Could not resolve host` (ns DNS goes through the tunnel); new magnets never fetch metadata (`totalSize=0`) — 2026-11-25's grabs were 0-byte for this reason, which is also what made them un-renamable during the Lidarr poison-torrent recovery.

### To do

- [ ] Regenerate a fresh PIA OpenVPN config (port-forwarding-capable region) and replace the contents of `secrets/pia-vpn.age` (`AGENIX_RULES=secrets/secrets.nix nix run github:ryantm/agenix#agenix -- -e secrets/pia-vpn.age`), then `sudo nixos-rebuild switch --flake .#melon` on melon. Note: the netns restart propagates to transmission (session reload, ~10 min) — acceptable. PF self-heals on its next 15-min run.
      **Use multiple `remote` lines this time** — the resilience work (working tree, 2026-11-25) makes the tunnel fail over across the whole set, and the watchdog re-pins them after a rotation. Replace PIA's single `remote <ip> <port>` with three hostname remotes (keep the port/proto from the generated file, keep `tun-mtu`/`mssfix`):
      ```
      remote ca-montreal.privacy.network <port>
      remote ca-toronto.privacy.network <port>
      remote ca-ontario.privacy.network <port>
      ```
      Hostnames (not IPs) are what let the watchdog detect a rotation. All three CA regions are `port_forward=true` (serverlist v6, checked 2026-11-25). After the switch, check one `pia-port-forward` run: the PF script uses the FIRST `remote` host as TLS SNI (`generic/server/arr.nix`), so if `getSignature` starts failing with curl 60 the gateway cert doesn't cover that hostname — report back and we'll split SNI from the connect target.
- [x] Exporter fix (working tree, 2026-11-25, pending deploy): openvpn creates `--status` 0600 and the exporter runs as an unprivileged DynamicUser — it has been serving "not readable" since the 2026-11-22 PIA move, which is the whole `up=0` story. The openvpn unit's post-start wait now `chmod 0644`s the status file (one chmod per start holds — openvpn rewrites the same inode each 10 s cycle).
- [x] `pia-tunnel-stalled` `noDataState` flipped to `Alerting` (working tree, 2026-11-25, pending deploy): unknown tunnel state is itself the emergency; with a healthy input the rule behaves as before.
- [x] Multi-remote failover + rotation watchdog (working tree, 2026-11-25, pending deploy): the netns unit now pins every `remote` (not just the first) and the tunnel unit passes them all to openvpn with `--remote-random`; `vpn-confinement-openvpn-watchdog@pia` (timer, 10 min) restarts the netns when the tunnel is stale AND resolution changed. See `VENDORED.md`.

### References

- `docs/debug/transmission.md` (PIA rotation signature)
- `docs/reports/2026-11-25-lidarr-poison-torrent.md` §4 (concurrent incident)
