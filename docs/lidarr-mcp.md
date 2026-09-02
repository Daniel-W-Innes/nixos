# Plan: give Claude Code full CRUD over Lidarr via MCP

Date: 2026-09-02
Goal: let Claude Code (running on melon, in this repo) manage Lidarr — artists, albums, releases, quality profiles, downloads — through MCP tools instead of clicking through the web UI.

## Decision

Run [`abl030/lidarr-mcp`](https://github.com/abl030/lidarr-mcp) (auto-generated from the Lidarr OpenAPI spec, 244 tools, full CRUD) as a **systemd service on melon** with FastMCP's streamable-http transport bound to **loopback** (`127.0.0.1:8001`), registered in the repo's project-scope `.mcp.json` as `http://127.0.0.1:8001/mcp`.

Not a traefik router: the server has mutation tools and no caller auth of its own, so it stays loopback-only on the host where Claude Code runs — same reasoning as `docs/mcp-grafana-plan.md`.

## Implementation

- **`flake.nix`** — `lidarr-mcp` input (`github:abl030/lidarr-mcp`, nixpkgs follows) passed to modules as `_module.args.lidarrMCP`.
- **`generic/server/arr.nix`** — `systemd.services.lidarr-mcp`:
  - Wraps `fastmcp run ${lidarrMCP}/generated/server.py "$@"`. The flake's default package is stdio-only (no `"$@"`), so a local `writeShellApplication` wrapper passes transport args.
  - `LIDARR_URL=http://127.0.0.1:8686` via `environment` (lidarr binds loopback; traefik proxies to it the same way).
  - `LIDARR_API_KEY` reuses the existing `lidarr-api-key.age` secret (same one exportarr-lidarr uses) via `LoadCredential`; the wrapper exports it from `$CREDENTIALS_DIRECTORY`. No second secret, no key duplication.
  - Runs as the `lidarr` user with `NoNewPrivileges`.
- **`.mcp.json`** — `lidarr-mcp` → `http://127.0.0.1:8001/mcp`.
- **`home/claude.nix`** — `enabledMcpjsonServers += "lidarr-mcp"`, and `permissions.allow` has the server-wide rule `mcp__lidarr-mcp` (write tools are the point of this server; enumerating 244 names would be noise).

## Facts (verified 2026-09-02)

- The flake's `default` package is a stdio-only wrapper; no published container image.
- `fastmcp run` http transport: `--transport http --host … --port …`; default path `/mcp/` (307-redirects `/mcp` → `/mcp/`, 200 on both via curl with redirect following).
- Server stays up when Lidarr is unreachable; tools fail per-call.
- Env vars: `LIDARR_URL` (default `http://localhost:8686`), `LIDARR_API_KEY` (required), `LIDARR_MODULES` (comma-separated module filter), `LIDARR_READ_ONLY` (strips all POST/PUT/DELETE tools).

## Deploy

```bash
# on melon
sudo nixos-rebuild switch --flake .#melon
```

## Verify

```bash
# on melon
systemctl status lidarr-mcp
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8001/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}'
# in Claude Code on melon: /mcp shows lidarr-mcp connected with 244 tools
```

## Optional hardening

- `LIDARR_READ_ONLY=true` if Claude should only read. `LIDARR_MODULES` can strip whole areas (e.g. `system,config`).
- If the endpoint ever needs to leave loopback, put it behind a traefik internal router (`internal-only` middleware) like the other `*.lc.brotherwolf.ca` services — deliberately not done here.
