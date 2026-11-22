# Adapts a host configuration into a QEMU test VM. Imported last in a test
# node so its overrides win.
#
# Smoke mode (withHostState = false): the VM boots the host's evaluated
# configuration with no access to host state and agenix disabled, so
# activation cannot fail on missing secrets. Safe for any local user and
# for CI (the unprivileged runner cannot read host state anyway).
#
# State mode (withHostState = true): the host's live /var/lib and /etc/ssh
# are shared into the VM read-only (9p with security_model=passthrough,
# which requires QEMU to run as root — hence the root-guarded wrappers in
# tests/vm-test.nix). /var/lib becomes an overlayfs whose lower is the host
# share and whose upper lives on the ephemeral VM disk, so the VM starts
# from the machine's real state while every guest write stays in the VM.
# /var/lib/containers is shadowed by a fresh tmpfs (podman storage must not
# sit on the overlay). agenix decrypts with the real host key from the
# shared /etc/ssh.
#
# Both modes run with restrictNetwork: the guest cannot reach the LAN or
# the internet, so no external side effects (ACME renewals, API calls).
{ withHostState }:
{
  config,
  lib,
  ...
}:

let
  # Units that must not start in the test VM: containers, secret-bearing or
  # heavy services, LAN/hardware-dependent units. The allowlists in
  # tests/vm-test.nix must never match one of these patterns.
  suppressPatterns = [
    "^(podman|docker)-.*\\.(service|timer)$"
    # Wifi declarative profiles need the wifi.age EnvironmentFile; the VM
    # has no wifi hardware.
    "^NetworkManager-ensure-profiles\\.service$"
    ".*(forgejo|gitea-runner).*"
    ".*(transmission|sonarr|radarr|prowlarr|lidarr|bazarr|readarr|flaresolverr|decluttarr|mixarr).*"
    ".*(proton|wireguard|gluetun).*"
    ".*(immich|audiomuse|bookorbit|blunderbase|dawarich|searx|meilisearch|calibre|jellyfin|navidrome).*"
    ".*(grafana|loki|tempo|alloy|influxdb|gotify|alertmanager|uptime|kuma).*"
    ".*exportarr.*"
    "^(postgres|redis|mariadb).*"
    ".*(airzone|openweathermap|konnected|iperf).*"
    ".*(unpoller|smokeping|shelly|statuspage|metar).*"
    ".*borgmatic.*"
    "nh-clean.*"
    ".*(bluetooth|bluez|smartd|thermald|tlp|cups).*"
    "^(display-manager|greetd|sddm|lightdm|gdm).*"
    ".*(zsa|ckb).*"
    ".*(speech|whisper).*"
  ]
  ++ lib.optionals (!withHostState) [
    # Smoke mode has no agenix secrets; traefik hard-fails on its missing
    # EnvironmentFile and crash-loops pointlessly. State mode asserts it
    # instead.
    "^traefik\\.service$"
  ];

  suppress = lib.filter (name: lib.any (re: builtins.match re name != null) suppressPatterns) (
    builtins.attrNames config.systemd.units
  );

  lower9pOptions = [
    "trans=virtio"
    "version=9p2000.L"
    "msize=${toString config.virtualisation.msize}"
    "ro"
    "x-systemd.requires=modprobe@9pnet_virtio.service"
  ];
in
{
  # Test nodes default this off (nixos-test-base.nix) to avoid rebuilding
  # switch-to-configuration; the whole point of this test is to run it.
  system.switch.enable = lib.mkForce true;

  # Keep the host's own initrd type: both the scripted initrd (stage-1
  # handles overlay prefixing and backing-dir creation) and the systemd
  # initrd (mount units + pre-mount services) support the boot-needed
  # overlay mounts in state mode.
  boot.initrd = {
    # The VM variant replaces services.xserver.videoDrivers with
    # "modesetting" (qemu-vm.nix), which disables hardware.nvidia and its
    # out-of-tree modules — but the host's initrd.kernelModules still lists
    # "nvidia", and the initrd module closure fails on it. Tolerate missing
    # modules: OOT drivers are hardware the VM doesn't have anyway.
    allowMissingModules = true;
  };

  systemd = {
    oomd.enable = lib.mkForce false;
    suppressedSystemUnits = lib.mkForce suppress;
  };

  virtualisation = {
    memorySize = lib.mkForce (if withHostState then 8192 else 4096);
    cores = lib.mkForce 4;
    diskSize = lib.mkForce (if withHostState then 32768 else 8192);
    graphics = lib.mkForce false;
    restrictNetwork = true;
    forwardPorts = lib.mkForce [ ];

    msize = lib.mkIf withHostState 262144;

    qemu.options = lib.optionals withHostState [
      "-virtfs local,path=/var/lib,mount_tag=host-var-lib,security_model=passthrough,readonly=on"
      "-virtfs local,path=/etc/ssh,mount_tag=host-etc-ssh,security_model=passthrough,readonly=on"
    ];

    fileSystems = lib.mkIf withHostState {
      "/mnt/host/var-lib" = {
        device = "host-var-lib";
        fsType = "9p";
        options = lower9pOptions;
        neededForBoot = true;
      };

      "/mnt/host/ssh" = {
        device = "host-etc-ssh";
        fsType = "9p";
        options = lower9pOptions;
        neededForBoot = true;
      };

      "/var/lib" = {
        overlay = {
          lowerdir = [ "/mnt/host/var-lib" ];
          upperdir = "/.vm/var-lib/upper";
          workdir = "/.vm/var-lib/work";
        };
        neededForBoot = true;
      };

      "/var/lib/containers" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [
          "mode=0700"
          "size=1G"
        ];
        neededForBoot = true;
      };
    };
  };

  # Smoke mode has no secrets: disable agenix so activation cannot fail on
  # undecryptable files. State mode reads the real host key from the shared
  # /etc/ssh (all secrets are encrypted to every host key, so any one host
  # key decrypts everything).
  age.enable = lib.mkForce withHostState;
  age.identityPaths = lib.mkIf withHostState (lib.mkForce [ "/mnt/host/ssh/ssh_host_ed25519_key" ]);
}
