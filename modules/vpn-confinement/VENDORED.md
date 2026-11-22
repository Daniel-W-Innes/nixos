# Vendored from github:nix-forge/vpn-confinement

Source: https://github.com/nix-forge/vpn-confinement
Revision: 8e4cd50e35fa573eb4e6b79b3a3257ee00c5e670
License: MIT

Local modifications (2026-11-22, PIA migration):

- Added an `openvpn` transport to the namespace options (`options.nix`):
  tunnel is a TUN device managed by the new
  `vpn-confinement-openvpn@<name>.service` unit instead of a
  `networking.wireguard.interfaces` entry.
- `lib.nix`: `tunnelInterface` helper; OpenVPN namespaces always get the
  hostLink (the tunnel daemon reaches its server through it pre-tunnel).
- `lifecycle.nix`: netns activation parses the .ovpn config at runtime,
  resolves each `remote`, and adds per-endpoint route + nftables exemptions
  through the hostLink; WireGuard assignments/units are skipped for OpenVPN
  namespaces; the OpenVPN tunnel unit runs openvpn in the foreground with
  systemd-managed restarts and waits for the tun address before activating.
- `service-extension.nix` / `socket-extension.nix`: confined units bind to
  the OpenVPN tunnel unit for OpenVPN namespaces.
- `firewall.nix`: policy rules key on the effective tunnel interface.
- `assertions.nix`: WireGuard interface requirements are skipped for
  OpenVPN namespaces; OpenVPN config/credentials/interface are validated.
- `diagnostics.nix`: manifest exposes the transport and tolerates missing
  WireGuard definitions for OpenVPN namespaces.

Upstreaming these changes back to nix-forge/vpn-confinement would be ideal;
until then this directory is the source of truth for the module.
