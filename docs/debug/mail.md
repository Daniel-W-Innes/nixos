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
   NB: stalwart-cli 2.0.0 has no `account` subcommand — it only does generic
   object CRUD (`create AccountPassword`, etc.); the webadmin is simpler.

## Symptoms

| Symptom | Check |
|---|---|
| `stalwart-provision` failed | `journalctl -u stalwart-provision -b`; schema errors would have failed the nix build instead. Wrong admin password → the credential key must match `admin.username` in `generic/server/stalwart.nix`. |
| mail temp-failed `451 4.3.5` | a milter is down (`systemctl status rspamd clamav-milter clamav-daemon`); milters fail closed (`tempFailOnError` defaults true). Deliberate. |
| `stalwart-delivery-failing` firing | outbound delivery is failing or retrying. Inbound 451 (down milter) does *not* queue, so this is outbound-only: once internet mail exists, check the queue in webadmin (Manage › Queue) for per-message errors and the recipient's MX health. |
| `stalwart-auth-failures` firing | credential attack (or a misconfigured client). Check `cscli alerts list`/`cscli decisions list` and webadmin's security/blocked IPs; the event log shows what's failing (`journalctl -u stalwart | grep -i auth`). |
| 587 `Host did not advertise authentication` | stalwart 1.x offers SASL only when `is_tls` (`MtaStageAuth.saslMechanisms` default) — our submission listener is plaintext. Fixed in `generic/server/stalwart.nix` (offer plain+login on all ports except 25); `require` defaults to `local_port != 25`, so 587 still demands AUTH. |
| spam not rejected | rspamd_proxy must bind 127.0.0.1:11332 with `milter = true`; test with a GTUBE body (see docs/testing.md-style swaks one-liner below). |
| virus not rejected | clamav-milter uses `OnInfected Reject` (not Quarantine — stalwart milters cannot stop delivery on a quarantine action, they only add an X-Quarantine header). Test with an EICAR attachment. |
| banned IPs not enforced | `sudo cscli decisions list`; `sudo nft list set ip crowdsec crowdsec-blacklists` (bouncer update_frequency is 10s, api_url `http://127.0.0.1:8083/`). |
| stalwart auth failures missing from crowdsec | auth.failed is a debug-level event and the Journal tracer only puts the event description in MESSAGE, so crowdsec's journalctl acquisition never saw the IP. Fixed 2026-11-27: `EventTracingLevel` raises auth.failed to info and a console tracer (restricted to auth.failed) serializes the full line into MESSAGE — see "CrowdSec parser" below. |
| `crowdsec.service` crash-loop: `mkdir /var/lib/crowdsec: permission denied` | the 26.05 bouncer register unit stole the state dir (its `StateDirectory=crowdsec` + `DynamicUser=true` triggers systemd's private-dir migration). One-time repair before re-switching: `sudo bash /tmp/crowdsec-state-cleanup.sh` (re-runnable — removes /var/lib/crowdsec, its private-dir copy, and the bouncer-register dirs); `generic/server/crowdsec.nix` fixes it (DynamicUser off on both units, static `crowdsec` user). |
| `crowdsec.service` fails with `226/NAMESPACE: /var/lib/crowdsec: No such file or directory` | systemd 260.5 can't set up `ProtectSystem=strict` mount namespacing when a `ReadWritePaths` path is missing — and that happens before `crowdsec-setup`'s ExecStartPre mkdir, so the daemon can never create it (register unit then cascades: cscli can't mkdir the trace dir as the static user). Fix without a switch: `sudo mkdir -p /var/lib/crowdsec && sudo chown crowdsec:crowdsec /var/lib/crowdsec && sudo systemctl reset-failed crowdsec.service crowdsec-firewall-bouncer-register.service crowdsec-firewall-bouncer.service && sudo systemctl start crowdsec.service crowdsec-firewall-bouncer-register.service crowdsec-firewall-bouncer.service`. Permanent fix: the tmpfiles rule in `generic/server/crowdsec.nix` pre-creates the dir. |
| bouncer register: `open /etc/crowdsec/config.yaml: no such file or directory` | the 26.05 register unit ran the bare cscli without `-c` (the crowdsec module only ever passes its config as a store path). Overridden in `generic/server/crowdsec.nix` — same logic, config passed explicitly. Registration is db-direct (cscli writes the LAPI sqlite, no HTTP — verified with crowdsec 1.7.8), so the unit runs as the static `crowdsec` user to write the LAPI db. |
| clamav-milter `Parse error ... Unknown option` | config must use clamav 1.x keywords: `OnFail` (not `OnError`), and `LogSyslog` no longer exists. |
| `stalwart-provision` times out; curl to 8088 gives empty reply; stalwart logs `Proxy protocol error` | `SystemSettings.proxyTrustedNetworks` makes stalwart 1.x *expect* the PROXY protocol from those networks — traefik speaks plain HTTP, so every connection is dropped, and normal mode can't be provisioned (chicken-and-egg: the bad setting lives in the DB). Fix: `proxyTrustedNetworks = []`, temporarily set `recovery.enable = true`, switch (the recovery API ignores those settings, provision applies the fix), then set recovery false and switch again. |

Test one-liners (swaks not installed on hosts: `nix shell nixpkgs#swaks -c swaks ...`).
Port 25 requires an FQDN in EHLO (`MtaStageEhlo.rejectNonFqdn` defaults on for
port 25 — deliberate), hence `--ehlo`:

```bash
# Round trip: submit on 587 (AUTH advertised via MtaStageAuth override).
# --from is required: mustMatchSender rejects senders that don't match the
# authenticated account (501 5.5.4 You are not allowed to send from this address).
swaks --server 127.0.0.1:587 --ehlo melon.brotherwolf.ca \
  --from daniel@brotherwolf.ca \
  --auth LOGIN --auth-user daniel@brotherwolf.ca --auth-password '<pw>' \
  --to daniel@brotherwolf.ca --body 'hello world'
# GTUBE must be rejected by rspamd
swaks --server 127.0.0.1:25 --ehlo melon.brotherwolf.ca --to daniel@brotherwolf.ca \
  --body 'XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X'
# EICAR attachment must be rejected by clamav-milter.
# --attach needs the @ prefix: swaks 20240103 removed the deprecated
# auto-file-detection, so without @ the path itself is attached as text.
printf 'X5O!P%%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > /tmp/eicar.txt
swaks --server 127.0.0.1:25 --ehlo melon.brotherwolf.ca --to daniel@brotherwolf.ca --attach @/tmp/eicar.txt
```

## CrowdSec parser

How stalwart auth failures reach CrowdSec (wired 2026-11-27, all verified in
1.2.0 source and with `cscli explain` against the real parser pipeline):

1. `auth.failed` logs at **debug** level by default (`EventType::level` falls
   through to `_ => Level::Debug`), so an `EventTracingLevel` object in
   `generic/server/stalwart.nix` raises it to info.
2. The **Journal** tracer puts only the event description in MESSAGE and the
   useful fields (remoteIp etc.) in structured journald fields — CrowdSec's
   journalctl acquisition reads only the short-format line, never those
   fields. A **console tracer** (`Tracer.objects.console`, `eventsPolicy =
   include` + `events = ["auth.failed"]` so nothing else is doubled) instead
   serializes the whole event onto stderr, which journald captures into
   MESSAGE as:
   `Nov 27 23:44:16 melon stalwart[1234]: 2026-11-27T23:44:16Z INFO Authentication failed (auth.failed) listenerId = "submission", localPort = 587, remoteIp = 192.168.1.5, ...`
3. The grok in `generic/server/crowdsec.nix` matches that line unanchored
   (CrowdSec does not strip the journalctl prefix for non-syslog types) and
   the statics map `remoteIp` → `evt.Meta.source_ip`. Validated with
   `cscli explain`: SMTP line matches, structured-Journal line does not
   (no duplicate events), IMAP + IPv6 variants match.

Stalwart's built-in auto-ban is **off** unless `Security.authBanRate` is
provisioned (schema has no default) — the repo does not set it, so CrowdSec is
currently the only IP-based mitigation; consider enabling it as a second layer.

Pending live verification after the next switch: burst ~6 failed AUTHs from
onion's LAN IP (bouncer stopped first so the SSH IP can't be banned), confirm
`sudo cscli alerts list` shows `local/stalwart-auth-bf`, delete the decision,
restart the bouncer.

## Visibility

- Metrics: `Metrics.prometheus = Enabled` (`generic/server/stalwart.nix`)
  serves `/metrics/prometheus` on the loopback HTTP listener, scraped by the
  `stalwart` Prometheus job (`generic/server/visibility.nix`). Useful series:
  `stalwart_auth_failed_total`, `stalwart_smtp_active_connections`,
  `stalwart_imap_active_connections`, `stalwart_store_rocksdb_error_total`,
  `stalwart_smtp_error_total`, `stalwart_queue_rescheduled_total`,
  `stalwart_delivery_*_failed_total`. **Gauge caveat (1.2.0):**
  `stalwart_queue_messages` is enterprise-only — the OSS build exports just
  `server_memory_bytes`/`users`/`domains` gauges plus per-protocol
  `active_connections`, so queue *size* is not visible until a newer version
  (it moved to the OSS gauge list upstream after 1.2.0). Counters appear only
  once non-zero, so absent series = zero events.
- Alerts (all severity critical, gotify via the shared contact point):
  `stalwart-down` (scrape fails), `stalwart-delivery-failing` (delivery
  failure/rejection counters or reschedules climbing for 15m — see symptoms
  below; window ages out past ~1h of retry backoff, a 1.2.0 limitation),
  `stalwart-auth-failures` (>0.1 auth failures/s sustained — credential
  attack; CrowdSec is the mitigation — stalwart's auto-ban is off unless
  `Security.authBanRate` is provisioned).
- Logs: the `Tracer` journal object ships everything to journald, which alloy
  forwards to Loki (`{unit="stalwart.service"}`) — no extra config. A second
  `Stdout` tracer restricted to `auth.failed` (ansi off) writes the
  CrowdSec-consumable lines to stderr (see "CrowdSec parser" above), so
  `auth.failed` appears in the journal twice (structured + console) — the only
  intentional duplication.
- Traces: a second `Tracer` object (`OtelGrpc`, log export off so Loki isn't
  double-fed) ships spans to alloy's `otelcol.receiver.otlp` (4319), which
  batches them to Tempo's OTLP-HTTP endpoint (4318). Query in Grafana Tempo
  as `service.name = "stalwart"`. **Dormant on 1.2.0**: the wiring is correct
  end-to-end (verified 2026-11-27: tracer object active after restart, alloy
  traces pipeline live, stalwart's OTLP sender connects lazily on first span)
  but 1.2.0 never emits one — the span framework exists upstream but the
  SMTP/IMAP/HTTP session code barely attaches span ids in this version (SMTP
  only on error events, IMAP not at all; upstream `main` has grown IMAP span
  support since). Expect spans to appear with a newer stalwart. Metrics
  deliberately stay on the Prometheus scrape — the OTel metrics exporter
  would just duplicate them into Prometheus and double-count rate() rules.
- Grafana artifact: `stalwart-queue-backlog` (the pre-1.2.0-gauge-finding
  rule) still lingers in Grafana after being removed from the file — Grafana
  does not delete file-provisioned rules that vanish from the provisioned
  rules.yaml. Harmless (evaluates NoData forever); delete it in the UI or via
  the API if it bothers you.

## Gotchas

- Rotating `stalwart-admin-password.age` does not restart services: run
  `systemctl restart stalwart stalwart-provision` afterwards.
- **Tracer changes are not hot-applied** — stalwart builds its tracer
  subscribers at startup, so provisioning a new `Tracer` object (e.g. the
  OtelGrpc spans tracer) takes effect only after `systemctl restart stalwart`
  (verified 2026-11-27: provision reconciled Tracer at 20:34, zero spans until
  restart; the provision `--reload` covers settings, not subscribers).
- Port map on melon: 8080 = traefik metrics, 8081/8082 = immich metrics
  (`generic/server/visibility.nix`), 8083 = crowdsec LAPI, 8088 = stalwart
  HTTP/admin/metrics. Don't reuse any of them.
- No internet mail until: DNS-01 certs, 465/993, MX/rDNS, public firewall.
  Current listeners are LAN-only; stalwart's built-in auto-ban stays on
  alongside CrowdSec.
