{ pkgs, ... }:

{
  virtualisation.containers.enable = true;
  virtualisation = {
    podman = {
      enable = true;
      autoPrune.enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = false;
    };
    oci-containers.backend = "podman";
  };

  # aardvark-dns answers on each custom bridge's gateway IP and containers
  # must reach it there. Wildcard because podman names bridges podmanN per
  # network (podman1 = bookorbit-net, podman2 = audiomuse-net) — a network
  # missing this rule fails every lookup with "Temporary failure in name
  # resolution" (2026-10-17 audiomuse incident).
  networking.firewall.extraInputRules = [
    ''iifname "podman*" udp dport 53 accept''
  ];

  environment.systemPackages = with pkgs; [
    dive
    podman-tui
  ];
}
