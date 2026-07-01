{ pkgs, lib, ... }:

{
  # IP forwarding required for exit node / subnet router
  boot.kernel.sysctl = lib.mkDefault {
    "net.ipv4.ip_forward" = true;
    "net.ipv6.conf.all.forwarding" = true;

    "net.ipv4.conf.all.accept_redirects" = false;
    "net.ipv4.conf.all.accept_source_route" = false;
    "net.ipv6.conf.all.accept_redirects" = false;
    "net.ipv6.conf.all.accept_source_route" = false;
    "net.ipv4.tcp_syncookies" = true;
  };

  # Allow only Traefik's entry points on the Tailscale interface
  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [
      80 # web (HTTP -> HTTPS redirect)
      443 # websecure (HTTPS)
    ];
    allowedUDPPorts = [
      53 # DNS
    ];
  };

  services.tailscale = {
    enable = true;
    authKeyFile = "/etc/tailscale/auth_key";
    extraUpFlags = [
      "--advertise-exit-node"
      "--ssh=false"
      "--accept-routes=false"
      "--accept-dns=false"
      "--webclient"
    ];
  };
  systemd.services.tailscale-dnsmasq-ip = {
    description = "Extract Tailscale IPv4 and write dnsmasq address file";
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    before = [ "dnsmasq.service" ];
    requiredBy = [ "dnsmasq.service" ];
    path = [ pkgs.tailscale ];
    script = ''
      set -e
      mkdir -p /run/tailscale-dnsmasq
      IP=$(${pkgs.tailscale}/bin/tailscale ip -4 2>/dev/null)
      if [ -z "$IP" ]; then
        echo "WARNING: tailscale ip -4 returned empty" >&2
        exit 0   # don't break the boot; dnsmasq will start without the wildcard
      fi
      echo "address=/lc.brotherwolf.ca/$IP" > "/run/tailscale-dnsmasq/address.conf"
    '';
    serviceConfig = {
      Type = "oneshot";
      RuntimeDirectory = "tailscale-dnsmasq";
      RemainAfterExit = true;
    };
  };

  services.dnsmasq = {
    enable = true;
    settings = {
      interface = "tailscale0";
      bind-interfaces = true;
      no-resolv = true;
      conf-dir = "/run/tailscale-dnsmasq,*.conf";
    };
  };
}
