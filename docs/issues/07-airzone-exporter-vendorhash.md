# airzone-exporter vendorHash drift breaks melon build

### Problem

`nixos-rebuild build --flake .#melon` fails (2026-09-06) with a hash mismatch in the fixed-output derivation `airzone-exporter-0.1.1-go-modules.drv`:

```
specified: sha256-lreLQdUZwXlrtte/8/kvqrRqUdeh/2ynqc4XDr2sIa4=
     got:    sha256-YtsKf5Jq+heotIhCV219PzTx6z5TueU1U+9XAlL4Nt0=
```

`vendorHash` in `modules/airzone-exporter.nix` still carries the old hash while the Go module cache the new nixpkgs pin produces hashes differently — likely a Go toolchain bump via the daily `nix flake update` workflow, since the module sources are unchanged. Pre-existing on `origin/master` (verified: master fails identically), but it makes every PR's melon CI check (`test.yml`) red until fixed. Same failure mode as the earlier `f5c180a fix sha go`.

### Fix

Update `vendorHash` in `modules/airzone-exporter.nix` to the hash the build reports:

```
vendorHash = "sha256-YtsKf5Jq+heotIhCV219PzTx6z5TueU1U+9XAlL4Nt0=";
```

Then rebuild melon and confirm the got-hash is stable (if it differs again, the Go toolchain isn't the whole story). While at it, check the sibling exporters — konnected built clean on 2026-09-06, but openweathermap should be verified too, since the same toolchain change affects every `buildGoModule` in the tree.

### Verification

- `nixos-rebuild build --flake .#melon` succeeds.
- CI `test.yml` goes green on the melon build.
- Journal/for next pin bump: no `hash mismatch` errors for any `*-go-modules.drv`.

### References

- `modules/airzone-exporter.nix` (vendorHash)
- `.forgejo/workflows/test.yml` (melon CI build)
- `f5c180a fix sha go` (same fix in module history)
