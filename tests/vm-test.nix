# VM-based switch tests for the hosts. Two modes per host, sharing one
# adapter module (vm-test-module.nix):
#
# checks.<host>-vm-test — smoke test, no host state. Boots the evaluated
# host configuration fresh, asserts the switch script runs cleanly and the
# core units come up. Runs in CI and for any local user.
#
# packages.<host>-vm-test-state — boots from the host's live state via
# overlayfs (see vm-test-module.nix) and additionally asserts the state
# plumbing (read-only 9p shares, ephemeral overlay upper, agenix decryption
# with the real host key). Requires root; never run it in CI.
#
# lib.vmTransitionTests.<host> baseFlake — old->new transition test. Boots
# the evaluated (new) configuration, switches to a VM-adapted generation of
# the base flake, and back — the real base -> new transition with unit
# restarts in both directions. No host state; safe for CI and local users.
# lib.vmTransitionStateTests.<host> baseFlake — the same on top of the live
# state plumbing (root only). The wrappers packages.<host>-vm-test-transition
# [-state] resolve baseFlake to a fresh checkout of master.
#
# See docs/testing.md for usage, limitations, and safety notes.
{
  pkgs,
  lib,
  system,
  hosts,
  mkHostModules,
}:

let
  inherit (lib)
    foldl'
    genAttrs
    mapAttrs'
    nameValuePair
    optionalString
    ;
  inherit (builtins) toJSON;

  # Tiny OCI image for the offline podman plumbing check: busybox ships the
  # applet multiplexer at /bin/busybox. Baked into the VM image via
  # virtualisation.additionalPaths (the store path is embedded in the test
  # scripts below) — no network, no real host containers.
  testImage = pkgs.dockerTools.buildImage {
    name = "vm-test-busybox";
    tag = "latest";
    copyToRoot = pkgs.busybox;
  };

  # Units that must come up in both modes. Secret-free by design: these are
  # the only units asserted in smoke mode, where agenix is disabled.
  commonUnits = [
    "sshd.service"
    "fail2ban.service"
    "avahi-daemon.service"
    "prometheus-node-exporter.service"
    "prometheus-process-exporter.service"
  ];

  policy = {
    melon = {
      probes = [
        "/var/lib/logrotate.status"
        "/var/lib/forgejo/postgres/PG_VERSION"
      ];
      stateUnits = commonUnits ++ [
        "NetworkManager.service"
        "prometheus.service"
        "traefik.service"
      ];
      secrets = [
        "forgejo-admin-password"
        "forgejo-db-password"
        "user-daniel"
      ];
      # Files the driver stats on the host before and after the run (the
      # driver executes on the host — see stateScript). Must never be
      # written by host services during the test window (logrotate.status
      # is deliberately excluded: logrotate may legitimately touch it).
      stableFiles = [
        "/var/lib/nixos/uid-map"
        "/etc/ssh/ssh_host_ed25519_key"
        "/var/lib/forgejo/postgres/PG_VERSION"
      ];
      extraAssertions = ''
        # Ownership matches the age.secrets declarations in
        # generic/server/forgejo.nix (forgejo user; uid 999 for the
        # postgres container).
        machine.succeed('test "$(stat -c %u /run/agenix/forgejo-admin-password)" = "$(id -u forgejo)"')
        machine.succeed('test "$(stat -c %u /run/agenix/forgejo-db-password)" = 999')
        machine.succeed('test "$(stat -c %a /run/agenix/forgejo-db-password)" = 400')
      '';
    };
    onion = {
      probes = [ "/var/lib/logrotate.status" ];
      stateUnits = commonUnits ++ [ "NetworkManager.service" ];
      secrets = [ "user-daniel" ];
      stableFiles = [
        "/var/lib/nixos/uid-map"
        "/etc/ssh/ssh_host_ed25519_key"
      ];
      extraAssertions = "";
    };
  };

  unitCheck = units: ''
    for unit in ${toJSON units}:
        machine.succeed("systemctl is-active " + unit)
  '';

  restartCheck = units: ''
    for unit in ${toJSON units}:
        machine.succeed("systemctl restart " + unit)
        machine.succeed("systemctl is-active " + unit)
  '';

  noFailed = ''
    machine.succeed('test -z "$(systemctl --failed --plain --no-legend)"')
  '';

  # The VM must boot through the real bootloader (EFI + systemd-boot, the
  # loader every non-secureBoot host uses) rather than the qemu-vm default
  # direct kernel boot. LoaderEntrySelected is written by systemd-boot
  # itself while booting, so its presence proves the boot went through the
  # loader.
  bootloaderCheck = ''
    machine.succeed("test -e /boot/loader/loader.conf")
    machine.succeed("test -e /boot/loader/entries/nixos-generation-1.conf")
    machine.succeed("test -e /sys/firmware/efi/efivars/LoaderEntrySelected-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f")
  '';

  # restrictNetwork (slirp with restrict=on) must keep the guest off the
  # internet — in state mode the guest holds the real secrets, so "no way
  # out" is a safety property worth asserting.
  networkCheck = ''
    machine.fail("ping -c 1 -W 1 -n 1.1.1.1")
  '';

  # The container plumbing works offline — storage driver, runtime, and (in
  # state mode) the tmpfs-shadowed container store. run --rm leaves no
  # containers behind.
  podmanCheck = ''
    machine.succeed("podman load -i ${testImage}")
    machine.succeed("podman run --rm vm-test-busybox:latest /bin/busybox true")
    machine.succeed('test -z "$(podman ps -aq)"')
  '';

  # Heavy/stateful services must stay off in the VM (they are suppressed by
  # vm-test-module.nix); guard against a suppression regression letting one
  # through. traefik is expected up in state mode (asserted in stateUnits),
  # so only smoke mode requires it off.
  offCheck = withHostState: ''
    machine.fail(
        "systemctl list-units --type=service --state=running --plain --no-legend | "
        + "grep -qE 'forgejo|gitea|sonarr|radarr|prowlarr|lidarr|bazarr|readarr|transmission|"
        + "postgres|audiomuse|immich|searx|jellyfin|navidrome|meilisearch|blunderbase|dawarich"
        + "${lib.optionalString (!withHostState) "|traefik"}'"
    )
  '';

  # The switch step is idempotent: a second run against the same generation
  # must also be clean, and every run must keep /run/current-system pointing
  # at the tested toplevel.
  switchCheck = units: newSystem: ''
    machine.succeed('test "$(readlink -f /run/current-system)" = "${newSystem}"')
    machine.succeed("/run/current-system/bin/switch-to-configuration test")
    machine.succeed('test "$(readlink -f /run/current-system)" = "${newSystem}"')
    ${unitCheck units}
    ${noFailed}
  '';

  # Boot-mode switch: activation plus a real bootloader install (bootctl
  # install, loader entries) against the VM's ESP — the mode that updates
  # /boot for the next reboot.
  bootSwitchCheck = newSystem: ''
    machine.succeed("/run/current-system/bin/switch-to-configuration boot")
    machine.succeed("grep -qF '${newSystem}' /boot/loader/entries/*.conf")
  '';

  smokeScript = newSystem: ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Booted through the real bootloader, running the tested toplevel.
    ${bootloaderCheck}
    machine.succeed('test "$(readlink -f /run/current-system)" = "${newSystem}"')

    # No host state, no secrets, no swap (melon's swapfile is stripped by
    # the VM variant), no way off the VM.
    machine.succeed("test ! -e /mnt/host")
    machine.succeed("test ! -e /run/agenix")
    machine.succeed("! mountpoint -q /var/lib")
    machine.succeed('test -z "$(swapon --show)"')
    ${networkCheck}

    ${unitCheck commonUnits}
    ${noFailed}

    # Home-manager activation ran for daniel (files are store symlinks) and
    # the unit reports success.
    machine.succeed("test -L /home/daniel/.zshrc")
    machine.succeed('test "$(systemctl show -p Result --value home-manager-daniel.service)" = success')

    # Heavy services stayed off.
    ${offCheck false}

    # Every core unit survives a restart.
    ${restartCheck commonUnits}

    # The container plumbing works offline.
    ${podmanCheck}

    # The point of the exercise: the activation + unit restart logic runs
    # cleanly against the booted system, twice (idempotency)...
    ${switchCheck commonUnits newSystem}
    ${switchCheck commonUnits newSystem}

    # ...and the boot-mode switch installs a real bootloader entry for it.
    ${bootSwitchCheck newSystem}
  '';

  stateScript = p: newSystem: ''
    import os
    host_snapshot = {path: os.stat(path).st_mtime_ns for path in ${toJSON p.stableFiles}}

    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Booted through the real bootloader, running the tested toplevel.
    ${bootloaderCheck}
    machine.succeed('test "$(readlink -f /run/current-system)" = "${newSystem}"')

    machine.succeed('test -z "$(swapon --show)"')

    # The guest holds the real secrets: it must have no way off the VM.
    ${networkCheck}

    # /var/lib is an overlay of the host share; the lower path keeps its
    # initrd /sysroot prefix after switch-root.
    machine.succeed("mountpoint -q /var/lib")
    machine.succeed("findmnt -n -o FSTYPE /var/lib | grep -qx overlay")
    machine.succeed("findmnt -n -o OPTIONS /var/lib | grep -Eq 'lowerdir=(/sysroot)?/mnt/host/var-lib'")

    # The host shares are 9p and read-only.
    machine.succeed("findmnt -n -o FSTYPE /mnt/host/var-lib | grep -q 9p")
    machine.succeed("findmnt -n -o OPTIONS /mnt/host/var-lib | grep -Eq '(^|,)ro(,|$)'")
    machine.succeed("findmnt -n -o FSTYPE /mnt/host/ssh | grep -q 9p")

    # Podman storage is shadowed by a fresh tmpfs.
    machine.succeed("mountpoint -q /var/lib/containers")
    machine.succeed("findmnt -n -o FSTYPE /var/lib/containers | grep -qx tmpfs")

    # Guest writes stay in the overlay upper and never reach the host.
    machine.fail("touch /mnt/host/var-lib/zz-vm-test")
    machine.fail("touch /mnt/host/ssh/zz-vm-test")
    machine.succeed("mkdir -p /var/lib/zz-vm-test && echo ok > /var/lib/zz-vm-test/marker")
    machine.succeed("test ! -e /mnt/host/var-lib/zz-vm-test")

    # The host's live state is visible through the overlay.
    for probe in ${toJSON p.probes}:
        machine.succeed("test -e " + probe)

    # Users and secrets: activation wrote the uid map and the shared host
    # key decrypted the real agenix secrets.
    machine.succeed("test -s /var/lib/nixos/uid-map")
    machine.succeed("getent passwd daniel")
    machine.succeed("grep -Eq '^daniel:[^!*]' /etc/shadow")
    machine.succeed("test -d /run/agenix")
    for secret in ${toJSON p.secrets}:
        machine.succeed("test -s /run/agenix/" + secret)
    ${p.extraAssertions}

    ${unitCheck p.stateUnits}
    ${noFailed}

    # Heavy services stayed off (traefik excluded: melon asserts it active).
    ${offCheck true}

    # Every state unit survives a restart on top of live state.
    ${restartCheck p.stateUnits}

    # The container plumbing works against the tmpfs-shadowed container
    # store.
    ${podmanCheck}

    # The switch runs cleanly against live state, twice (idempotency)...
    ${switchCheck p.stateUnits newSystem}
    ${switchCheck p.stateUnits newSystem}

    # ...and the boot-mode switch installs a real bootloader entry for it.
    ${bootSwitchCheck newSystem}

    # The driver runs on the host: stat the real files and require them
    # untouched by the VM.
    for path, mtime_ns in host_snapshot.items():
        assert os.stat(path).st_mtime_ns == mtime_ns, f"host path {path} was modified by the VM test"
  '';

  # Rolls to the base generation and back. The last switch is the real
  # old -> new transition: /run/current-system is the base generation and
  # every unit whose definition changed is restarted by the new
  # switch-to-configuration. The booted system path is captured at runtime
  # (it is the VM's own /run/current-system before the first switch).
  transitionTail = units: oldSystem: ''
    machine.succeed("readlink -f /run/current-system > /run/vm-test-new-system")

    # Roll forward to the base generation (VM-adapted, so activation is
    # clean even without host state). /run/current-system must follow each
    # switch.
    machine.succeed("${oldSystem}/bin/switch-to-configuration test")
    machine.succeed('test "$(readlink -f /run/current-system)" = "${oldSystem}"')
    ${unitCheck units}
    ${noFailed}

    # And back: the real base -> new transition.
    machine.succeed("$(cat /run/vm-test-new-system)/bin/switch-to-configuration test")
    machine.succeed('test "$(readlink -f /run/current-system)" = "$(cat /run/vm-test-new-system)"')
    ${unitCheck units}
    ${noFailed}
  '';

  transitionScript = oldSystem: ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    ${bootloaderCheck}

    machine.succeed("test ! -e /mnt/host")
    machine.succeed("test ! -e /run/agenix")
    machine.succeed('test -z "$(swapon --show)"')
    ${networkCheck}

    ${unitCheck commonUnits}
    ${noFailed}
    ${offCheck false}

    ${transitionTail commonUnits oldSystem}
  '';

  transitionStateScript = p: oldSystem: ''
    import os
    host_snapshot = {path: os.stat(path).st_mtime_ns for path in ${toJSON p.stableFiles}}

    machine.start()
    machine.wait_for_unit("multi-user.target")

    ${bootloaderCheck}

    machine.succeed('test -z "$(swapon --show)"')
    # The guest holds the real secrets: it must have no way off the VM.
    ${networkCheck}
    machine.succeed("mountpoint -q /var/lib")
    machine.succeed("findmnt -n -o FSTYPE /var/lib | grep -qx overlay")
    machine.succeed("findmnt -n -o FSTYPE /mnt/host/var-lib | grep -q 9p")
    machine.succeed("findmnt -n -o FSTYPE /mnt/host/ssh | grep -q 9p")

    # The shared host key decrypts the real secrets in this mode too.
    machine.succeed("test -d /run/agenix")
    for secret in ${toJSON p.secrets}:
        machine.succeed("test -s /run/agenix/" + secret)

    for probe in ${toJSON p.probes}:
        machine.succeed("test -e " + probe)

    ${unitCheck p.stateUnits}
    ${noFailed}

    ${transitionTail p.stateUnits oldSystem}

    for path, mtime_ns in host_snapshot.items():
        assert os.stat(path).st_mtime_ns == mtime_ns, f"host path {path} was modified by the VM test"
  '';

  mkTest =
    {
      hostName,
      withHostState,
      oldBaseFlake ? null,
    }:
    let
      p = policy.${hostName};
      nodeModule = import ./vm-test-module.nix { inherit withHostState; };
      # The old generation must be built as a test node too: the plain host
      # toplevel's agenix activation would fail in the VM (the
      # guest-generated SSH keys are no valid recipients), and — the
      # reason it must be a full test-node build — switch-to-configuration
      # stops every unit present in the current system but absent from the
      # target. Without the test framework modules below, switching to the
      # plain old toplevel would stop backdoor.service (the driver's shell),
      # the store/shared-dir mounts and the VLAN unit, killing the test
      # connection mid-switch. The framework modules must come from the
      # base's own nixpkgs: importing this flake's copies would duplicate
      # option declarations (e.g. virtualisation.diskSize is part of the
      # base module list in the base's rev) and fail evaluation.
      # NB: `.config` must be selected from the let-bound result — Nix
      # parses `f { x = 1; }.config` as `f ({x = 1;}.config)`.
      oldSystem =
        if oldBaseFlake == null then
          null
        else
          let
            baseSystem = (builtins.getFlake oldBaseFlake).nixosConfigurations.${hostName};
            oldExtended = baseSystem.extendModules {
              modules = [
                (baseSystem.pkgs.path + "/nixos/modules/virtualisation/qemu-vm.nix")
                (baseSystem.pkgs.path + "/nixos/lib/testing/nixos-test-base.nix")
                (baseSystem.pkgs.path + "/nixos/modules/testing/test-instrumentation.nix")
                (import ./vm-test-module.nix { inherit withHostState; })
              ];
            };
          in
          oldExtended.config.system.build.toplevel;
    in
    pkgs.testers.runNixOSTest {
      name = "${hostName}-vm-test${optionalString withHostState "-state"}${
        optionalString (oldSystem != null) "-transition"
      }";
      # The host configs set nixpkgs.config (allowUnfree); the test
      # framework's read-only nixpkgs module would conflict.
      node.pkgsReadOnly = false;
      nodes.machine = {
        imports =
          mkHostModules hostName hosts.${hostName}
          ++ [
            nodeModule
          ]
          ++ lib.optionals (oldSystem != null) [
            {
              # The image must hold two toplevel closures. mkOverride 60
              # outranks the adapter's mkForce (priority 50).
              virtualisation.diskSize = lib.mkOverride 60 32768;
            }
          ];
        # Extra store paths baked into the VM image: the old generation's
        # closure (transition) or the podman test image (smoke/state).
        virtualisation.additionalPaths =
          lib.optional (oldSystem != null) oldSystem ++ lib.optionals (oldSystem == null) [ testImage ];
      };
      testScript =
        { nodes, ... }:
        let
          newSystem = builtins.toString nodes.machine.system.build.toplevel;
        in
        if oldSystem != null then
          (if withHostState then transitionStateScript p oldSystem else transitionScript oldSystem)
        else if withHostState then
          stateScript p newSystem
        else
          smokeScript newSystem;
    };

  smokeTests = genAttrs [ "melon" "onion" ] (
    hostName:
    mkTest {
      inherit hostName;
      withHostState = false;
    }
  );
  stateTests = genAttrs [ "melon" "onion" ] (
    hostName:
    mkTest {
      inherit hostName;
      withHostState = true;
    }
  );

  stateWrapper =
    interactive: hostName:
    pkgs.writeShellScriptBin "${hostName}-vm-test-state${optionalString interactive "-interactive"}" ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "error: ${hostName}-vm-test-state shares the host's /var/lib and /etc/ssh" >&2
        echo "       into the VM (9p passthrough) and must run as root." >&2
        echo "Run: sudo env TMPDIR=/var/tmp nix run .#packages.${system}.${hostName}-vm-test-state" >&2
        exit 1
      fi
      exec ${
        stateTests.${hostName}.${if interactive then "driverInteractive" else "driver"}
      }/bin/nixos-test-driver "$@"
    '';

  # Transition wrappers: the old generation is master, checked out to a
  # temp worktree and re-evaluated with the VM adapter by the test itself.
  transitionWrapper =
    withHostState: interactive: hostName:
    let
      flakeFn = if withHostState then "vmTransitionStateTests" else "vmTransitionTests";
      drvSel = if interactive then "driverInteractive" else "driver";
    in
    pkgs.writeShellScriptBin "${hostName}-vm-test-transition${optionalString withHostState "-state"}${optionalString interactive "-interactive"}" ''
      set -e
      # Resolve the checkout at runtime: ${toString ../.} bakes in the
      # flake's store copy, which has no .git and was always rejected. The
      # wrapper only ever runs from a human's shell inside their clone.
      repo="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        echo "error: must be run from inside the repo git checkout" >&2
        exit 1
      }
      base_dir="$(mktemp -d /var/tmp/vm-transition-base.XXXXXX)"
      trap 'rm -rf "$base_dir"' EXIT
      if ! git -C "$repo" worktree add --detach "$base_dir/base" master >/dev/null 2>&1; then
        # master may be checked out elsewhere; a plain archive works too.
        mkdir -p "$base_dir/base"
        git -C "$repo" archive master | tar -x -C "$base_dir/base"
      fi
      ${lib.optionalString withHostState ''
        if [ "$(id -u)" -ne 0 ]; then
          echo "error: ${hostName}-vm-test-transition-state shares the host's /var/lib and /etc/ssh" >&2
          echo "       into the VM (9p passthrough) and must run as root." >&2
          echo "Run: sudo env TMPDIR=/var/tmp nix run .#packages.${system}.${hostName}-vm-test-transition-state" >&2
          exit 1
        fi
      ''}
      out="$(nix build --no-link --print-build-logs --print-out-paths --impure --expr "
        let pr = builtins.getFlake \"path:$repo\";
        in (pr.lib.${flakeFn}.${hostName} \"path:$base_dir/base\").${drvSel}
      " | tail -1)"
      exec "$out/bin/nixos-test-driver" "$@"
    '';

  # Functions from the base flake path to the transition test (the old
  # generation is re-evaluated with the VM adapter inside mkTest).
  transitionTests = genAttrs [ "melon" "onion" ] (
    hostName: baseFlakePath:
    mkTest {
      inherit hostName;
      oldBaseFlake = baseFlakePath;
      withHostState = false;
    }
  );
  transitionStateTests = genAttrs [ "melon" "onion" ] (
    hostName: baseFlakePath:
    mkTest {
      inherit hostName;
      oldBaseFlake = baseFlakePath;
      withHostState = true;
    }
  );
in
{
  checks = mapAttrs' (hostName: test: nameValuePair "${hostName}-vm-test" test) smokeTests;

  packages =
    foldl'
      (
        acc: hostName:
        acc
        // {
          "${hostName}-vm-test-driver" = smokeTests.${hostName}.driver;
          "${hostName}-vm-test-driver-interactive" = smokeTests.${hostName}.driverInteractive;
          "${hostName}-vm-test-state" = stateWrapper false hostName;
          "${hostName}-vm-test-state-interactive" = stateWrapper true hostName;
          "${hostName}-vm-test-transition" = transitionWrapper false false hostName;
          "${hostName}-vm-test-transition-interactive" = transitionWrapper false true hostName;
          "${hostName}-vm-test-transition-state" = transitionWrapper true false hostName;
          "${hostName}-vm-test-transition-state-interactive" = transitionWrapper true true hostName;
        }
      )
      { }
      [
        "melon"
        "onion"
      ];

  # Exposed for the CI workflow and the transition wrappers: functions from
  # a base flake path to the corresponding transition test. Only called
  # from impure evaluations (the wrappers / --expr in CI), so the
  # builtins.getFlake inside is fine; pure evals never force these.
  vmTransitionTests = transitionTests;
  vmTransitionStateTests = transitionStateTests;
}
