# Mail stack (Stalwart) playbook

Stalwart 1.2 (vendored post-26.11 module, `modules/stalwart/`) with rspamd +
clamav-milter + CrowdSec on melon. No TLS/DNS-01/ACME/DKIM yet — listeners are
plaintext and LAN-only (see `generic/server/stalwart.nix`).

## Bootstrap sequence (one-time)

1. The first switch must run with `services.stalwart.recovery.enable = true`
   (`generic/server/stalwart.nix`): stalwart starts without mail listeners,
   serving the management API on 127.0.0.1:8088, and
   `stalwart-provision.service` applies the whole provision plan (the plan is
   validated against the 1.x OSS schema at **build** time).
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
| spam not rejected | rspamd_proxy must bind 127.0.0.1:11332 with `milter = true`; test with a GTUBE body (see docs/testing.md-style swaks one-liner below). |
| virus not rejected | clamav-milter uses `OnInfected Reject` (not Quarantine — stalwart milters cannot stop delivery on a quarantine action, they only add an X-Quarantine header). Test with an EICAR attachment. |
| banned IPs not enforced | `sudo cscli decisions list`; `sudo nft list set ip crowdsec crowdsec-blacklists` (bouncer update_frequency is 10s). |
| stalwart logs missing from crowdsec | the parser is a deliberate no-match scaffold (`generic/server/crowdsec.nix`) — see TODO below. |

Test one-liners (swaks not installed on hosts: `nix shell nixpkgs#swaks -c swaks ...`):

```bash
# GTUBE must be rejected by rspamd
swaks --server 127.0.0.1:25 --to daniel@brotherwolf.ca \
  --body 'XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X'
# EICAR attachment must be rejected by clamav-milter
printf 'X5O!P%%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > /tmp/eicar.txt
swaks --server 127.0.0.1:25 --to daniel@brotherwolf.ca --attach /tmp/eicar.txt
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
- 8088 (stalwart HTTP) and 8081 (crowdsec LAPI) were chosen because 8080 is
  traefik's metrics listener on melon.
- No internet mail until: DNS-01 certs, 465/993, MX/rDNS, public firewall.
  Current listeners are LAN-only; stalwart's built-in auto-ban stays on
  alongside CrowdSec.
