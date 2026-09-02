# Plan: give Claude Code access to the visibility services via MCP

Date: 2026-08-30 (updated 2026-08-31: run on onion instead of melon)
Goal: let Claude Code (running on onion, in this repo) query the observability stack on melon — Prometheus, Loki, Grafana dashboards/alerts — through MCP tools instead of only editing config.

## Decision

Run the official standalone [`grafana/mcp-grafana`](https://github.com/grafana/mcp-grafana) server as an oci-container **on onion** (next to Claude Code) with the `streamable-http` transport bound to loopback, and register it in the repo's project-scope `.mcp.json`. Grafana itself is reached over the existing tailscale route (`grafana.lc.brotherwolf.ca`), so no new traefik router is needed.

## Why not Grafana's built-in MCP server

Grafana core does not have one (verified 2026-08-30):

- grafana 13.0.3 binary on melon (`/nix/store/...-grafana-13.0.3/bin/grafana`, 347 MB Go binary): `strings | grep -ci mcp` → 0
- `conf/defaults.ini`: no `[mcp_server]` section
- `https://grafana.com/docs/grafana/latest/mcp/` → 404

Grafana's MCP support is client-side (the MCP datasource plugin), not a server. A patch bump to 13.0.6 (pinned) will not add it.

## mcp-grafana facts (verified from README, 2026-08-31)

- Repo: `grafana/mcp-grafana`, active (last push 2026-08-30), Docker/binary/Helm installs.
- Tools include: PromQL instant/range queries, Loki log queries (with byte-cost guardrail, `--loki-guardrail-mode`), dashboards, alert rules, contact points, annotations, panel/dashboard PNG rendering, Sift.
- Datasource coverage: Prometheus, Loki, ClickHouse, CloudWatch, Elasticsearch/OpenSearch, Snowflake, Athena, Quickwit. **No InfluxDB or Tempo tools.**
- Container image: **`docker.io/grafana/mcp-grafana`** (Docker Hub). The older `ghcr.io/grafana/mcp-grafana` reference no longer pulls — ghcr returns 403 DENIED on anonymous token requests for all `grafana/*` packages (verified 2026-08-31 from onion; `prometheus/*` still works, so it is org-wide, not network-specific).
- Auth to Grafana: `GRAFANA_URL` + `GRAFANA_SERVICE_ACCOUNT_TOKEN` (Grafana service account token; `GRAFANA_API_KEY` is deprecated).
- Transport flags: `-t/--transport` (`stdio` default, `sse`, `streamable-http`), `--address` (default `localhost:8000`), `--endpoint-path` (default `/mcp`), `--allowed-hosts` (Host-header allowlist; non-loopback `Host` → 403), `--server-auth-token` (optional caller auth; binding a non-loopback address without it logs a security error). The image entrypoint defaults to SSE mode; `cmd` overrides it.
- Not packaged in nixpkgs 26.05 (checked `pkgs/` for `mcp-grafana`/prometheus-MCP; nix search shows only unrelated MCP servers).

## Implementation steps

### 1. Container on onion — `generic/grafana-mcp.nix`

Imported from `generic/desktop.nix`. Adds to `virtualisation.oci-containers.containers`:

```nix
mcp-grafana = {
  image = "docker.io/grafana/mcp-grafana:latest"; # TODO: consider pinning a tag/digest
  environmentFiles = [ config.age.secrets.grafana-mcp-env.path ];
  extraOptions = [ "--network=host" ];
  cmd = [
    "--transport" "streamable-http"
    "--address" "127.0.0.1:8000"             # loopback bind: avoids the non-loopback-without-caller-auth security error
  ];
};
```

The container uses **host networking** instead of a published port: podman's port publish forwards to the container's eth0, where a loopback-bound server isn't listening, so bridge + `ports` refuses connections (verified 2026-08-31). With `--network=host` the loopback bind lands on the host's loopback directly and Claude Code reaches it with no forwarder in between.

No traefik router, no `--allowed-hosts` (loopback `Host` is in the default allowlist), no firewall changes. The container reaches Grafana through onion's DNS (`grafana.lc.brotherwolf.ca` → melon over tailscale), with Let's Encrypt certs the Go binary trusts.

### 2. agenix secret — onion only

`nix shell nixpkgs#agenix -c agenix -e secrets/grafana-mcp-env.age` with content:

```
GRAFANA_URL=https://grafana.lc.brotherwolf.ca
GRAFANA_SERVICE_ACCOUNT_TOKEN=<service-account-token>
```

- Create the Grafana service account with the **Viewer** role (write tools then fail closed). Editor if Claude should manage dashboards/alerts.
- Entry exists in `secrets/secrets.nix` (onion can decrypt). The token never appears in the repo.

### 3. Project `.mcp.json` — repo root

No headers needed (loopback-only endpoint; no secrets on the client side):

```json
{
  "mcpServers": {
    "mcp-grafana": {
      "type": "http",
      "url": "http://127.0.0.1:8000/mcp"
    }
  }
}
```

### 4. Permissions allowlist

In `home/claude.nix` via `programs.claude-code.settings` (settings.json is home-manager-managed):

```json
{
  "enabledMcpjsonServers": ["mcp-grafana"],
  "permissions": {
    "allow": [
      "mcp__mcp-grafana__query_prometheus",
      "mcp__mcp-grafana__query_loki_logs",
      "mcp__mcp-grafana__list_dashboards",
      "mcp__mcp-grafana__get_dashboard",
      "mcp__mcp-grafana__list_alert_rules",
      "mcp__mcp-grafana__get_alert_rule"
    ]
  }
}
```

Exact tool names will show in `/mcp` after the first connect — adjust. Deny any write tools if the SA role is Editor.

### 5. Deploy

```bash
# on onion
sudo nixos-rebuild switch --flake .#onion
```

## Quick-start alternative (skip step 1)

Stdio works immediately once the image is pulled (no router, no published port; credentials stay in the container env):

```json
"mcp-grafana": {
  "command": "podman",
  "args": ["exec", "-i", "mcp-grafana", "mcp-grafana"]
}
```

## Out of scope (Tempo, InfluxDB, Gotify, host ops)

- mcp-grafana has no InfluxDB/Tempo tools. Cover with narrow Bash allow rules, e.g.
  `Bash(curl -sS https://influx.lc.brotherwolf.ca/...)` with a token in the environment.
- Host-level ops (restart services, journalctl) are Bash permission rules, not MCP:
  `Bash(journalctl *)`, `Bash(systemctl status *)`, `Bash(ssh melon systemctl *)` (keep ssh patterns narrow — the permission matcher can't see the remote command).

## Optional hardening

- Set `--server-auth-token` on the container and add a `Bearer ${GRAFANA_MCP_TOKEN}` header in `.mcp.json`. Loopback-only binding makes this mostly redundant; defense in depth if the endpoint is ever exposed.
- Pin the container image tag/digest instead of `:latest`.

## Verify after deploy

```bash
# on onion: container is up and healthy
podman ps --filter name=mcp-grafana
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8000/healthz

# in Claude Code: /mcp shows mcp-grafana connected with its tool list
```
