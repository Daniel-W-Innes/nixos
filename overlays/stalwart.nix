# Package backports for the vendored services.stalwart module
# (modules/stalwart/, nixpkgs PR #552103 — see modules/stalwart/VENDORED.md).
#
# stalwart_1 and rocksdb_11_8 must build with nixpkgs-unstable's rustPlatform:
# 26.05's rustc (1.95) is below stalwart 1.2.0's MSRV (1.98, required by
# mail-parser 1.0.2). stalwart-cli builds fine on 26.05 and stays there.
# Package files are vendored verbatim from nixpkgs master (versions and hashes
# pinned), so the versions do not drift with the unstable input.
unstable: final: _: {
  stalwart_1 = unstable.callPackage ../pkgs/stalwart_1/package.nix { };
  rocksdb_11_8 = unstable.callPackage ../pkgs/rocksdb_11_8/package.nix { };
  stalwart-cli = final.callPackage ../pkgs/stalwart-cli/package.nix { };
}
