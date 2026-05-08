_:

{
  imports = [
    ../podman.nix
    ./arr.nix
    ./visibility.nix
    ./smb.nix
    ./jellyfin.nix
    ./dawarich.nix
    # > Checking runtime dependencies for calibreweb-0.6.25-py3-none-any.whl
    # >   - requests<2.33.0,>=2.32.0 not satisfied by version 2.33.1
    # ./calibre.nix
    ./traefik.nix
  ];
}
