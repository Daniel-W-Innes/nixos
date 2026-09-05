# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal NixOS configuration flake for three machines (single `x86_64-linux` system, single user `daniel`):

| Host | Type | Notes |
|------|------|-------|
| `melon` | server | Self-hosted services behind traefik (forgejo, arr stack, searx, immich, ...) |
| `onion` | desktop | niri, steam, forgejo runner, mcp-grafana (MCP to the observability stack) |
| `cucamelon` | laptop | Secure Boot via lanzaboote |

Pinned to `nixpkgs/nixos-26.05` and `home-manager/release-26.05`; home-manager and agenix `follow` nixpkgs. There is no devShell — the repo is the config itself. Deployed by running `nixos-rebuild switch --flake .` on each machine (hostname matches the `nixosConfigurations` attr name).

## Commands

```bash
# Build one host without deploying
nix build .#nixosConfigurations.melon.config.system.build.toplevel
nixos-rebuild build --flake .#melon

# Apply changes (run on the target machine; `--flake .` matches hostname)
sudo nixos-rebuild switch --flake .#melon

# Format (nixfmt-tree)
nix fmt

# Checks: nix flake check runs the pre-commit hook suite
# (deadnix, nil, statix, ripsecrets, trufflehog — configured in flake.nix, not .pre-commit-config.yaml)
nix flake check
prek run [hook]          # e.g. `prek run statix` for a single hook; no arg runs all

# Update the lockfile (also done daily by the Forgejo update workflow)
nix flake update

# Edit / rekey agenix secrets (rekey after adding a host's key to secrets/secrets.nix)
nix shell nixpkgs#agenix -c agenix -e secrets/foo.age
nix shell nixpkgs#agenix -c agenix -r
```

## Architecture

`flake.nix` is the hub. `mkHost` assembles each `nixosConfigurations.<name>` from:

1. `sharedModules` — agenix, nixos-facter, home-manager, nix-index-database, lanzaboote, the custom modules in `./modules`, plus `_module.args.secretsDir = ./secrets`
2. `hosts/<name>/configuration.nix` + `facter.json` (hardware report consumed via `config.facter.reportPath`)
3. `generic/<type>.nix` — NixOS system module for the machine class
4. a home-manager module built from `home/<type>.nix`

The `hosts` attrset in `flake.nix` maps hostname → `{ type, stateVersion, secureBoot, extraModules }`. Adding a machine means adding a `hosts/<name>/` directory, an entry there, and matching `generic/`/`home/` files for the type.

- **`generic/`** — system modules keyed by machine class. `min.nix` is the common base imported by server/desktop/laptop. `generic/server.nix` imports `generic/server/*.nix`, one file per self-hosted service (traefik, forgejo, arr, smb, searx, uptime, weather, visibility...). Modules may take `secretsDir`/`secureBoot` from `_module.args` (see `generic/min.nix` branching on `secureBoot`).
- **`home/`** — home-manager configs keyed by machine class, composed from shared pieces (`base.nix`, `min.nix`, `term.nix`, `niri.nix`, `gui.nix`, ...). WM-specific config lives in per-WM subdirectories (`home/niri/config.kdl`, `home/hyprland/`, `home/sway/`). Home-manager runs as a NixOS module (`users.daniel`, global pkgs) — not standalone.
- **`modules/`** — custom NixOS modules: three Prometheus exporters (konnected, airzone, openweathermap) written in Go and built inline with `pkgs.buildGoModule` (`src = ./<dir>`, pinned `vendorHash`), plus `services.bookorbit`. `modules/konnected-exporter/gotify/` is a generated OpenAPI client. When Go sources change, update `vendorHash` (the build prints the expected hash).
- **`secrets/`** — agenix `.age` files. `secrets/secrets.nix` maps each secret to the SSH keys (per-user and per-host) allowed to decrypt it; new hosts must be added there and all secrets rekeyed. Modules reference them as `age.secrets.<name>.file = secretsDir + /<name>.age`; runtime path is `config.age.secrets.<name>.path` (`/run/agenix/<name>` by default — `/run/secrets/...` references inside container definitions are in-container mount targets, not agenix paths).
- **MCP** — `mcp-grafana` runs as an oci-container on onion (`generic/grafana-mcp.nix`, imported by `generic/desktop.nix`), bound to host loopback via `--network=host`, giving Claude Code MCP tools for Grafana/Prometheus/Loki. `lidarr-mcp` runs as a systemd service on onion (`generic/lidarr-mcp.nix`, imported by `generic/desktop.nix`), loopback-bound streamable-http, reusing `lidarr-api-key.age` via `LoadCredential` and reaching Lidarr on melon over the internal traefik route. Both are registered in the repo-root `.mcp.json`; tool allowlist is in `home/claude.nix` (`programs.claude-code.settings`). Full rationale and steps: `docs/mcp-grafana-plan.md`, `docs/lidarr-mcp.md`.

## CI (self-hosted Forgejo Actions at git.lc.brotherwolf.ca)

- **`.forgejo/workflows/test.yml`** — on PRs and pushes to `master`, builds `melon` and `onion` with `nixos-rebuild build --flake .` on self-hosted runners (the machines themselves), then diffs the closure against `/run/current-system` and master using `dix`. `cucamelon` is not built in CI.
- **`.forgejo/workflows/update.yml`** — daily `nix flake update`, force-pushes branch `update/flake-inputs`, and opens/refreshes a PR via the Forgejo REST API using an OIDC JWT.

## Conventions and gotchas

- Anonymous pulls of `ghcr.io/grafana/*` images return 403 DENIED (org-wide, verified 2026-08-31; `ghcr.io/prometheus/*` works) — use `docker.io/grafana/<image>` instead.
- oci-containers publishes ports to the container's **eth0**, not its loopback: an app binding `127.0.0.1` inside the container is unreachable via a published port (symptom: `ss` shows LISTEN but connections are refused). Use `extraOptions = [ "--network=host" ]` for loopback-bound servers (see `generic/grafana-mcp.nix`).
- Editing an agenix env-file secret does **not** restart its podman container — `nixos-rebuild switch` only restarts units whose definition changed, so the old env stays loaded. Run `sudo systemctl restart podman-<name>` after rotating the secret.
- `~/.claude/settings.json` is home-manager-managed via `programs.claude-code.settings` in `home/claude.nix`; a pre-existing unmanaged file makes `home-manager-daniel.service` fail activation.
- `statix` ignores `**/hardware-configuration.nix` (generated by `nixos-generate-config`; `facter.json` by `nixos-facter`).
- `stateVersion` is pinned per host in `flake.nix` — leave it alone.
- `secureBoot = true` (cucamelon) switches boot from plain systemd-boot to lanzaboote; this branches on the `secureBoot` module arg.
- CI runs on the target machines themselves, so `melon`/`onion` must be online for PR checks to pass.
- process-exporter `cmdline` regexes in one group are **ANDed** (one regex with `|` alternation for OR), and its `-children` flag defaults to true, so groups count the matched process plus its descendants.
