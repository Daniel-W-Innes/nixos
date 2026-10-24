{ pkgs, ... }:

{
  hardware.ckb-next = {
    enable = true;
    # nixpkgs' 0.6.2-unstable-2025-09-25 predates upstream's Scimitar RGB
    # Elite support (ckb-next@20a3df9a, merged 2025-11-03 — a "bragi"
    # generation device). Override to master until a tagged release includes
    # it. The Elite has no hardware playback (settings are software-only), so
    # the daemon must keep running for remaps/RGB to stay active.
    package = pkgs.ckb-next.overrideAttrs (_: {
      version = "0.6.2-unstable-2026-10-21";
      src = pkgs.fetchFromGitHub {
        owner = "ckb-next";
        repo = "ckb-next";
        rev = "e22eaf2fba7f93764b4c6d4413bb83eeca75d10a";
        hash = "sha256-v/qazMy25SETYJcYMGW91ZuLL1YoPdCwwkPn899TDyM=";
      };
    });
  };
}
