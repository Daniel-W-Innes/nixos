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
| `packages.<host>-vm-test-transition` | none | agenix disabled | any local user, CI step |
| `packages.<host>-vm-test-transition-state` | live `/var/lib` + `/etc/ssh` | real host key | **root only, never CI** |

Smoke/state boot the *new* toplevel (the evaluated config) in the VM and then run
`/run/current-system/bin/switch-to-configuration test` inside it, asserting that
activation and the unit restart logic run cleanly.

The transition modes add the missing piece: they boot the new config, **switch
to a VM-adapted generation of the base flake** (`master` for the local wrappers;
the base branch in CI), and then **switch back** — so the final switch is a real
old→new transition: `/run/current-system` is the old generation and every unit
whose definition changed between the two is genuinely restarted by the new
activation logic. The old generation is re-evaluated as a full test node
(`nixosConfigurations.<host>.extendModules` + the base nixpkgs'
`qemu-vm`/`nixos-test-base`/`test-instrumentation` modules + the VM adapter):
the plain host toplevel's agenix activation would fail in the VM (the
guest-generated SSH keys are not valid recipients), and without the test
framework modules the switch would stop the driver's own units
(`backdoor.service`, the store/shared-dir mounts) and kill the test connection.

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
# Everything at once: both hosts, every mode the current user may run.
# Writes per-test logs + a SUMMARY.md index to ~/vm-test-logs/<timestamp>
# (also reachable via ~/vm-test-logs/latest) — paste it into an AI with @<path>.
tests/run-vm-tests.sh
tests/run-vm-tests.sh --hosts onion            # just this host
tests/run-vm-tests.sh --with-state             # include the root-only state tests (sudo)
tests/run-vm-tests.sh smoke transition         # just these modes

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

# Transition test: boot the built config, switch to a VM-adapted master
# generation and back (checks out master to a temp worktree itself).
nix run .#packages.x86_64-linux.onion-vm-test-transition

# Transition on live state — root only.
sudo env TMPDIR=/var/tmp nix run .#packages.x86_64-linux.onion-vm-test-transition-state
```

Run the state tests on the machine they target (its `/var/lib` and host key are
the ones shared). CI runs the smoke check and the transition test — the Forgejo
runner is unprivileged and cannot read host state (and should never be granted
it; CI executes PR code, so anything CI can read, any PR can read).

## What is asserted

All modes: no failed units after boot and after each switch; the core units
(sshd, fail2ban, avahi, node/process exporters) active before and after every
switch; `switch-to-configuration test` exits 0; heavy services stay off
(suppression guard); the switch step is run twice (idempotency).

Smoke additionally: no `/mnt/host`, no `/run/agenix`, no swap, home-manager
links present for `daniel`, every core unit survives a `systemctl restart`.

State additionally: `/var/lib` is an overlay of the host share (ro 9p lower,
`/sysroot` prefix tolerated in the options), `/var/lib/containers` is tmpfs,
`touch` on the shares fails, a guest marker written under `/var/lib` does not
appear in the host share, host probes exist (logrotate.status; melon also probes
the forgejo postgres dir), `daniel` has a password hash, agenix secrets exist
with the declared owners/modes, the state allowlist (adds NetworkManager,
prometheus, traefik on melon) is active before and after the switch and survives
a `systemctl restart`, and — since the driver runs on the host — the mtime of
the host's `uid-map`, SSH host key, and (melon) `PG_VERSION` is asserted
unchanged after the run.

Transition additionally: after switching to the old generation, units are
active and no units failed; the same after switching back.

## Limitations

- The old generation of the transition test is `master`/base as re-evaluated
  with the VM adapter — not the host's own deployed toplevel (which cannot be
  adapted post-hoc without its module source). The deployed config is
  represented by the live state in the state modes instead.
- The overlay lower is a snapshot at boot, not a live mirror (COW semantics;
  atime on host files may still be updated by 9p reads).
- Containers/DBs do not start in phase 1 (suppressed; podman storage is
  shadowed). Starting them against live DB state is future work.
- The unit suppression list in `tests/vm-test-module.nix` is broad
  (deny-by-default for heavy/secret-bearing/LAN services); new host services
  may start unexpectedly until a pattern is added.
- Transition tests embed two toplevel closures in the VM image (32 GiB disk) —
  they build and run slower than the smoke test.
- The transition direction base→new is only meaningful while the unit
  definitions actually differ; for no-op changes the switch restarts nothing
  and the test still passes (it asserts the activation is clean).

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
