# Mail stack (Stalwart) playbook

Stalwart 1.2 (vendored post-26.11 module, `modules/stalwart/`) with rspamd +
clamav-milter + CrowdSec on melon. No TLS/DNS-01/ACME/DKIM yet — listeners are
plaintext and LAN-only (see `generic/server/stalwart.nix`).

## Bootstrap sequence (one-time)

1. The first switch must run with `services.stalwart.recovery.enable = true`
   (`generic/server/stalwart.nix`): stalwart starts without mail listeners,
   serving the management API on 127.0.0.1:8088, and
   `stalwart-provision.service` applies the whole provision plan (the plan is
   validated against the 1.x OSS schema at **build** time). Done on melon
   2026-11-27 — the repo now has `recovery.enable = false`.
2. Verify: `systemctl show -p Result --value stalwart-provision` = success;
   `curl -fsS http://127.0.0.1:8088/healthz/live`.
3. Set `recovery.enable = false`, switch again: listeners 25/587/143 and the
   traefik route come up.
4. Set daniel@brotherwolf.ca's password once (webadmin at
   https://stalwart.lc.brotherwolf.ca as `stalwart-admin`, or `stalwart-cli`).

## Symptoms

| Symptom | Check |
|---|---|
| `stalwart-provision` failed | `journalctl -u stalwart-provision -b`; schema errors would have failed the nix build instead. Wrong admin password → the credential key must match `admin.username` in `generic/server/stalwart.nix`. |
| mail temp-failed `451 4.3.5` | a milter is down (`systemctl status rspamd clamav-milter clamav-daemon`); milters fail closed (`tempFailOnError` defaults true). Deliberate. |
| 587 `Host did not advertise authentication` | stalwart 1.x offers SASL only when `is_tls` (`MtaStageAuth.saslMechanisms` default) — our submission listener is plaintext. Fixed in `generic/server/stalwart.nix` (offer plain+login on all ports except 25); `require` defaults to `local_port != 25`, so 587 still demands AUTH. |
| spam not rejected | rspamd_proxy must bind 127.0.0.1:11332 with `milter = true`; test with a GTUBE body (see docs/testing.md-style swaks one-liner below). |
| virus not rejected | clamav-milter uses `OnInfected Reject` (not Quarantine — stalwart milters cannot stop delivery on a quarantine action, they only add an X-Quarantine header). Test with an EICAR attachment. |
| banned IPs not enforced | `sudo cscli decisions list`; `sudo nft list set ip crowdsec crowdsec-blacklists` (bouncer update_frequency is 10s, api_url `http://127.0.0.1:8083/`). |
| stalwart logs missing from crowdsec | the parser is a deliberate no-match scaffold (`generic/server/crowdsec.nix`) — see TODO below. |
| `crowdsec.service` crash-loop: `mkdir /var/lib/crowdsec: permission denied` | the 26.05 bouncer register unit stole the state dir (its `StateDirectory=crowdsec` + `DynamicUser=true` triggers systemd's private-dir migration). One-time repair before re-switching: `sudo bash /tmp/crowdsec-state-cleanup.sh` (re-runnable — removes /var/lib/crowdsec, its private-dir copy, and the bouncer-register dirs); `generic/server/crowdsec.nix` fixes it (DynamicUser off on both units, static `crowdsec` user). |
| `crowdsec.service` fails with `226/NAMESPACE: /var/lib/crowdsec: No such file or directory` | systemd 260.5 can't set up `ProtectSystem=strict` mount namespacing when a `ReadWritePaths` path is missing — and that happens before `crowdsec-setup`'s ExecStartPre mkdir, so the daemon can never create it (register unit then cascades: cscli can't mkdir the trace dir as the static user). Fix without a switch: `sudo mkdir -p /var/lib/crowdsec && sudo chown crowdsec:crowdsec /var/lib/crowdsec && sudo systemctl reset-failed crowdsec.service crowdsec-firewall-bouncer-register.service crowdsec-firewall-bouncer.service && sudo systemctl start crowdsec.service crowdsec-firewall-bouncer-register.service crowdsec-firewall-bouncer.service`. Permanent fix: the tmpfiles rule in `generic/server/crowdsec.nix` pre-creates the dir. |
| bouncer register: `open /etc/crowdsec/config.yaml: no such file or directory` | the 26.05 register unit ran the bare cscli without `-c` (the crowdsec module only ever passes its config as a store path). Overridden in `generic/server/crowdsec.nix` — same logic, config passed explicitly. Registration is db-direct (cscli writes the LAPI sqlite, no HTTP — verified with crowdsec 1.7.8), so the unit runs as the static `crowdsec` user to write the LAPI db. |
| clamav-milter `Parse error ... Unknown option` | config must use clamav 1.x keywords: `OnFail` (not `OnError`), and `LogSyslog` no longer exists. |
| `stalwart-provision` times out; curl to 8088 gives empty reply; stalwart logs `Proxy protocol error` | `SystemSettings.proxyTrustedNetworks` makes stalwart 1.x *expect* the PROXY protocol from those networks — traefik speaks plain HTTP, so every connection is dropped, and normal mode can't be provisioned (chicken-and-egg: the bad setting lives in the DB). Fix: `proxyTrustedNetworks = []`, temporarily set `recovery.enable = true`, switch (the recovery API ignores those settings, provision applies the fix), then set recovery false and switch again. |

Test one-liners (swaks not installed on hosts: `nix shell nixpkgs#swaks -c swaks ...`).
Port 25 requires an FQDN in EHLO (`MtaStageEhlo.rejectNonFqdn` defaults on for
port 25 — deliberate), hence `--ehlo`:

```bash
# Round trip: submit on 587 (AUTH advertised via MtaStageAuth override)
swaks --server 127.0.0.1:587 --ehlo melon.brotherwolf.ca \
  --auth LOGIN --auth-user daniel@brotherwolf.ca --auth-password '<pw>' \
  --to daniel@brotherwolf.ca --body 'hello world'
# GTUBE must be rejected by rspamd
swaks --server 127.0.0.1:25 --ehlo melon.brotherwolf.ca --to daniel@brotherwolf.ca \
  --body 'XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X'
# EICAR attachment must be rejected by clamav-milter
printf 'X5O!P%%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > /tmp/eicar.txt
swaks --server 127.0.0.1:25 --ehlo melon.brotherwolf.ca --to daniel@brotherwolf.ca --attach /tmp/eicar.txt
```

## CrowdSec parser TODO

The parser grok in `generic/server/crowdsec.nix` is a placeholder that matches
nothing (fail-safe: no events, no bans) until real samples replace it:

1. Fail SMTP AUTH / IMAP LOGIN on purpose from a LAN client.
2. `journalctl -u stalwart -o cat --since '5 min ago' | grep -iE 'auth|login'`
   → sample lines.
3. `sudo cscli explain --log '<line>' --type stalwart -v`, iterate the grok
   until events carry `log_type=stalwart_auth_failure` + `source_ip`; then
   trigger a burst and confirm `sudo cscli alerts list` fires.

## Gotchas

- Rotating `stalwart-admin-password.age` does not restart services: run
  `systemctl restart stalwart stalwart-provision` afterwards.
- Port map on melon: 8080 = traefik metrics, 8081/8082 = immich metrics
  (`generic/server/visibility.nix`), 8083 = crowdsec LAPI, 8088 = stalwart
  HTTP/admin. Don't reuse any of them.
- No internet mail until: DNS-01 certs, 465/993, MX/rDNS, public firewall.
  Current listeners are LAN-only; stalwart's built-in auto-ban stays on
  alongside CrowdSec.
