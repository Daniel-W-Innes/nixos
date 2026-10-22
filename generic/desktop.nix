_:

{
  imports = [
    ./min.nix
    ./hypr.nix
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
    ./server/audiomuse.nix
    ./forgejoRunner.nix
    ./lokiShipper.nix
    ./speech.nix
  ];

  # AudioMuse workers pulling from melon's postgres over the LAN (melon
  # publishes 5433; mTLS + scram). "melon" resolves via the router's
  # DHCP-lease DNS, which the worker containers can use (containers have no
  # mDNS, so melon.local would not resolve there) and which auto-tracks
  # melon's IP. Analysis is CPU-heavy and melon is capped at 2 local
  # replicas (64-core oversubscription, 2026-10-17); onion's 16 threads take
  # one replica without contention — raise `workers` for future library
  # imports, minding the 16-thread budget (each replica's ONNX inference is
  # multi-threaded).
  services.audiomuse = {
    workerOnly = true;
    # Burst capacity for the initial onboarding scan only — flip to false
    # and switch once the scan is done (units disappear, containers removed).
    workerEnabled = true;
    workers = 1;
    postgresHost = "melon";
    postgresPort = 5433;
  };

  # Expose alloy's HTTP server on the LAN so melon's Prometheus can scrape its
  # pipeline metrics (loki_write retries, journal lines read, ...). pprof stays
  # loopback-only; the alloy UI is served on this port too (no auth in 1.16).
  services.alloy.extraFlags = [
    "--server.http.listen-addr=0.0.0.0:12345"
    "--server.http.enable-pprof=false"
  ];

  networking.firewall.interfaces."enp8s0".allowedTCPPorts = [ 12345 ];
}
