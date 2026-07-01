_:

{
  # IP forwarding required for exit node / subnet router
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = true;
    "net.ipv6.conf.all.forwarding" = true;

    "net.ipv4.conf.all.accept_redirects" = false;
    "net.ipv4.conf.all.accept_source_route" = false;
    "net.ipv6.conf.all.accept_redirects" = false;
    "net.ipv6.conf.all.accept_source_route" = false;
    "net.ipv4.tcp_syncookies" = true;
  };

  # Allow only Traefik's entry points on the Tailscale interface
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
    80 # web (HTTP -> HTTPS redirect)
    443 # websecure (HTTPS)
  ];

  services.tailscale = {
    enable = true;
    authKeyFile = "/etc/tailscale/auth_key";
    extraUpFlags = [
      "--advertise-exit-node"
      "--ssh=false"
      # "--advertise-routes=192.168.1.0/24"
    ];
  };
}
