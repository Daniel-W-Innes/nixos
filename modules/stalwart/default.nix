# Vendored from NixOS/nixpkgs PR #552103 (see VENDORED.md). Upstream
# nixos/modules/module-list.nix registers two entries; this wrapper mirrors
# that so the vendored files below import unchanged.
{
  # nixos-26.05 still ships the pre-0.16 stalwart module in its default
  # module list, and both modules declare the same options
  # (services.stalwart + the services.stalwart-mail rename). Disable the
  # built-in one so this vendored replacement's options win.
  disabledModules = [ "services/mail/stalwart.nix" ];

  imports = [
    ./stalwart.nix
    ./provision.nix
  ];
}
