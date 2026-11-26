# Vendored from NixOS/nixpkgs PR #552103

Source: https://github.com/NixOS/nixpkgs/pull/552103
Revision: d155af3766b774ec7b01424b7b23b38b3c8e2c9a (2026-11-24, PR open/unmerged at vendoring time)
License: MIT

Files:
- stalwart.nix              <- nixos/modules/services/mail/stalwart/default.nix (renamed)
- provision.nix             <- nixos/modules/services/mail/stalwart/provision.nix
- provision-check-sort.lua  <- nixos/modules/services/mail/stalwart/provision-check-sort.lua

Local modifications (2026-11-25):

- Upstream default.nix renamed to stalwart.nix; a new default.nix wrapper
  imports both module entries (mirrors the two lines in
  nixos/modules/module-list.nix) and carries `disabledModules = [
  "services/mail/stalwart.nix" ]`: nixos-26.05's default module list still
  contains the pre-0.16 module, which collides with this one.
- Upstream stalwart.md (meta.doc) is dropped: its section headings create
  manual anchors (module-services-stalwart-{recovery,databases,bootstrap,
  usage,provision,upgrading}) that only exist in the PR's
  nixos/doc/manual/redirects.json, which this repo's nixpkgs doesn't have,
  so the NixOS manual build fails. Option documentation still renders from
  the option declarations themselves.
- Otherwise no content changes in the vendored files.

This is the post-26.11 module shape (services.stalwart.admin/provision/url
for Stalwart 0.16+/1.x). The nixos-26.05 module supports only 0.15.5, so the
packages are backported too (overlays/stalwart.nix + pkgs/stalwart_1/,
pkgs/rocksdb_11_8/, pkgs/stalwart-cli/). The overlay builds stalwart_1 and
rocksdb_11_8 with nixpkgs-unstable's rustPlatform — 26.05's rustc 1.95 is
below stalwart 1.2.0's MSRV of 1.98 — while keeping the vendored package.nix
versions/hashes pinned.

Exit strategy: when the repo's nixpkgs pin reaches a release containing the
merged module (target: 26.11), delete modules/stalwart/, overlays/stalwart.nix,
pkgs/stalwart_1/, pkgs/rocksdb_11_8/ and pkgs/stalwart-cli/, drop the overlay
from melon's extraModules in flake.nix and the `imports = [ ../../modules/stalwart ]`
line from generic/server/stalwart.nix. The services.stalwart configuration is
the upstream option surface and should carry over unchanged — diff the merged
module's options (stateVersion thresholds, admin credentials, provision
objects) before switching package attrs.
