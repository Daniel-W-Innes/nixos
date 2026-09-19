_:

{
  imports = [
    ./min.nix
    ./ssh.nix
    ./displayManager.nix
    ./hypr.nix
    ./iperf.nix
    ./prometheus.nix
    ./avahi.nix
    ./smartd.nix
    ./wifi.nix
    ./lokiShipper.nix
  ];
  # The quickshell bar reads battery state over UPower; off by default.
  services.upower.enable = true;
}
