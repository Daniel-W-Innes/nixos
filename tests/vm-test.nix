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
      extraAssertions = "";
    };
  };

  unitCheck = units: ''
    for unit in ${toJSON units}:
        machine.succeed("systemctl is-active " + unit)
  '';

  smokeScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # No host state, no secrets, no swap (melon's swapfile is stripped by
    # the VM variant).
    machine.succeed("test ! -e /mnt/host")
    machine.succeed("test ! -e /run/agenix")
    machine.succeed("! mountpoint -q /var/lib")
    machine.succeed('test -z "$(swapon --show)"')

    ${unitCheck commonUnits}

    # The point of the exercise: the activation + unit restart logic runs
    # cleanly against the booted system.
    machine.succeed("/run/current-system/bin/switch-to-configuration test")

    ${unitCheck commonUnits}
  '';

  stateScript = p: ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    machine.succeed('test -z "$(swapon --show)"')

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

    machine.succeed("/run/current-system/bin/switch-to-configuration test")

    ${unitCheck p.stateUnits}
  '';

  mkTest =
    { hostName, withHostState }:
    let
      p = policy.${hostName};
      nodeModule = import ./vm-test-module.nix { inherit withHostState; };
    in
    pkgs.testers.runNixOSTest {
      name = "${hostName}-vm-test${optionalString withHostState "-state"}";
      # The host configs set nixpkgs.config (allowUnfree); the test
      # framework's read-only nixpkgs module would conflict.
      node.pkgsReadOnly = false;
      nodes.machine = {
        imports = mkHostModules hostName hosts.${hostName} ++ [ nodeModule ];
      };
      testScript = if withHostState then stateScript p else smokeScript;
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
        }
      )
      { }
      [
        "melon"
        "onion"
      ];
}
