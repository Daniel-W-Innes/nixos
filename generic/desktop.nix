_:

{
  imports = [
    ./min.nix
    ./niri.nix
    ./iperf.nix
    ./displayManager.nix
    ./prometheus.nix
    ./ssh.nix
    ./wifi.nix
    ./steam.nix
    ./avahi.nix
    ./claude.nix
    ./grafana-mcp.nix
    ./lidarr-mcp.nix
    ./smartd.nix
    ./borgmatic.nix
    ./podman.nix
    ./forgejoRunner.nix
    ./lokiShipper.nix
  ];

  # Expose alloy's HTTP server on the LAN so melon's Prometheus can scrape its
  # pipeline metrics (loki_write retries, journal lines read, ...). pprof stays
  # loopback-only; the alloy UI is served on this port too (no auth in 1.16).
  services.alloy.extraFlags = [
    "--server.http.listen-addr=0.0.0.0:12345"
    "--server.http.enable-pprof=false"
  ];

  networking.firewall.interfaces."enp8s0".allowedTCPPorts = [ 12345 ];
}
