# Plan: give Claude Code full CRUD over Lidarr via MCP

Date: 2026-09-02
Goal: let Claude Code (running on onion, in this repo) manage Lidarr — artists, albums, releases, quality profiles, downloads — through MCP tools instead of clicking through the web UI.

## Decision

Run [`abl030/lidarr-mcp`](https://github.com/abl030/lidarr-mcp) (auto-generated from the Lidarr OpenAPI spec, 244 tools, full CRUD) as a **systemd service on onion** (next to Claude Code, like `mcp-grafana`) with FastMCP's streamable-http transport bound to **loopback** (`127.0.0.1:8001`), registered in the repo's project-scope `.mcp.json` as `http://127.0.0.1:8001/mcp`. Lidarr itself is reached over the existing internal traefik route (`https://lidarr.lc.brotherwolf.ca`), so no new traefik router is needed — same shape as `docs/mcp-grafana-plan.md`.

Not on melon: the MCP server must sit next to the client (loopback-only endpoint, no caller auth of its own), and `generic/server/*` modules never apply to onion.

## Implementation

- **`flake.nix`** — `lidarr-mcp` input (`github:abl030/lidarr-mcp`, nixpkgs follows) passed to modules as `_module.args.lidarrMCP`.
- **`generic/lidarr-mcp.nix`** (imported by `generic/desktop.nix`) — `systemd.services.lidarr-mcp`:
  - Wraps `fastmcp run ${lidarrMCP}/generated/server.py "$@"`. The flake's default package is stdio-only (no `"$@"`), so a local `writeShellApplication` wrapper passes transport args.
  - `LIDARR_URL=https://lidarr.lc.brotherwolf.ca` via `environment` (internal-only traefik router, Let's Encrypt certs the Python httpx client trusts).
  - `LIDARR_API_KEY` reuses the existing `lidarr-api-key.age` secret (the same file exportarr-lidarr uses on melon), declared here too so agenix materializes it on onion, and injected via `LoadCredential`; the wrapper exports it from `$CREDENTIALS_DIRECTORY`. No second secret, no key duplication.
  - `DynamicUser` + `NoNewPrivileges`.
- **`.mcp.json`** — `lidarr-mcp` → `http://127.0.0.1:8001/mcp`.
- **`home/claude.nix`** — `enabledMcpjsonServers += "lidarr-mcp"`, and `permissions.allow` has the server-wide rule `mcp__lidarr-mcp` (write tools are the point of this server; enumerating 244 names would be noise).

## Facts (verified 2026-09-02)

- The flake's `default` package is a stdio-only wrapper; no published container image.
- `fastmcp run` http transport: `--transport http --host … --port …`; default path `/mcp/` (307-redirects `/mcp` → `/mcp/`, 200 on both via curl with redirect following).
- Server stays up when Lidarr is unreachable; tools fail per-call.
- Env vars: `LIDARR_URL` (default `http://localhost:8686`), `LIDARR_API_KEY` (required), `LIDARR_MODULES` (comma-separated module filter), `LIDARR_READ_ONLY` (strips all POST/PUT/DELETE tools).

## Deploy

```bash
# on onion
sudo nixos-rebuild switch --flake .#onion
```

## Verify

```bash
# on onion: service is up and healthy
systemctl status lidarr-mcp
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8001/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}'
# in Claude Code on onion: /mcp shows lidarr-mcp connected with 244 tools
```

## Optional hardening

- `LIDARR_READ_ONLY=true` if Claude should only read. `LIDARR_MODULES` can strip whole areas (e.g. `system,config`).
- If the endpoint ever needs to leave loopback, put it behind a traefik internal router (`internal-only` middleware) like the other `*.lc.brotherwolf.ca` services — deliberately not done here.
