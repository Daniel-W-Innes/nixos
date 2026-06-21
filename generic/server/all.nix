_:

{
  imports = [
    ../podman.nix
    ./arr.nix
    ./visibility.nix
    ./smb.nix
    ./dawarich.nix
    # TODO: Fix calibre the SQLite database doesn't work with CIFS.
    # ./calibre.nix
    ./bookorbit.nix
    ./immich.nix
    ./traefik.nix
    ./meilisearch.nix
    ./searx.nix
    ./weather.nix
    ./akvorado.nix
  ];
}
