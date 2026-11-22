# VM switch tests

Boot a host's configuration in a QEMU VM and run the switch machinery against it,
so a broken `nixos-rebuild switch` is caught before it touches the live machine.

The harness is `tests/vm-test.nix` + `tests/vm-test-module.nix`, wired into
`checks`/`packages` by `flake.nix` via `mkHostModules` (the exact module list of
each host, reused so the VM evaluates the real configuration).

## Modes

| Output | Host state | Secrets | Who may run it |
|---|---|---|---|
| `checks.<host>-vm-test` (smoke) | none | agenix disabled | any local user, CI |
| `packages.<host>-vm-test-state` | live `/var/lib` + `/etc/ssh` via 9p + overlayfs | real agenix decryption with the host key | **root only, never CI** |

Both modes boot the *new* toplevel (the evaluated config) in the VM and then run
`/run/current-system/bin/switch-to-configuration test` inside it, asserting that
activation and the unit restart logic run cleanly.

### State mode mechanics

- QEMU shares the host's `/var/lib` and `/etc/ssh` read-only
  (`-virtfs ...,security_model=passthrough,readonly=on`; passthrough requires
  QEMU as root).
- `/var/lib` is an overlayfs: lower = host share, upper/work = ephemeral dirs on
  the VM disk. Every guest write lands in the upper — the host is never written.
- `/var/lib/containers` is shadowed by a fresh tmpfs (podman storage must not
  sit on the overlay).
- agenix reads the real host key from the shared `/etc/ssh` (all secrets are
  encrypted to every host key, so any one host key decrypts everything).
- `restrictNetwork` isolates the guest: no LAN, no internet, no external side
  effects (ACME renewals, API calls).

## Commands

```bash
# Smoke test (no host state) — safe for CI and any local user.
nix build --no-link --print-build-logs .#checks.x86_64-linux.onion-vm-test

# Interactive smoke debugging (REPL).
nix run .#packages.x86_64-linux.onion-vm-test-driver-interactive
#   machine.start()
#   machine.shell_interact()

# Full state test — root only. TMPDIR on disk: the driver puts a sparse disk
# image there, and /tmp is tmpfs on onion.
sudo env TMPDIR=/var/tmp nix run .#packages.x86_64-linux.onion-vm-test-state

# Interactive state debugging.
sudo env TMPDIR=/var/tmp nix run .#packages.x86_64-linux.onion-vm-test-state-interactive
```

Run the state test on the machine it targets (its `/var/lib` and host key are
the ones shared). CI runs only the smoke checks — the Forgejo runner is
unprivileged and cannot read host state (and should never be granted it; CI
executes PR code, so anything CI can read, any PR can read).

## What is asserted

Smoke: no `/mnt/host`, no `/run/agenix`, no swap, core units active
(sshd, fail2ban, avahi, node/process exporters), `switch-to-configuration test`
exits 0, units still active.

State: additionally — `/var/lib` is an overlay of the host share (ro 9p lower,
`/sysroot` prefix tolerated in the options), `/var/lib/containers` is tmpfs,
`touch` on the shares fails, a guest marker written under `/var/lib` does not
appear in the host share, host probes exist (logrotate.status; melon also probes
the forgejo postgres dir), `daniel` has a password hash, agenix secrets exist
with the declared owners/modes, the state allowlist (adds NetworkManager,
prometheus, traefik on melon) is active before and after the switch.

## Limitations

- The VM boots the new generation directly — there is no old→new unit
  transition, only the activation script's unit management against real state.
- The overlay lower is a snapshot at boot, not a live mirror (COW semantics;
  atime on host files may still be updated by 9p reads).
- Containers/DBs do not start in phase 1 (suppressed; podman storage is
  shadowed). Starting them against live DB state is future work.
- The unit suppression list in `tests/vm-test-module.nix` is broad
  (deny-by-default for heavy/secret-bearing/LAN services); new host services
  may start unexpectedly until a pattern is added.

## Safety

State mode mounts the machine's own `/var/lib` and SSH host key into a root
guest on the same machine — intended for the operator on their own host. Never
run it on a multi-user machine, and never give the CI runner root or a KVM
state test: a writable passthrough 9p of the host root would be a root
equivalent.

## Tuning

After changing host services, re-tune via an interactive run:
`systemctl --failed` and `systemctl list-units --state=running` in the guest;
add suppression patterns in `tests/vm-test-module.nix`, adjust per-host
allowlists/probes in `tests/vm-test.nix`.
