{
  pkgs,
  plasmaZones,
  ...
}:

{
  imports = [ plasmaZones.nixosModules.default ];

  # Dormant: not imported by generic/desktop.nix or generic/laptop.nix.
  # To activate: swap ./niri.nix for ./kde.nix (and in home/*.nix) and remove
  # ./displayManager.nix — ly conflicts with sddm.
  services.desktopManager.plasma6 = {
    enable = true;
    # Pure Qt 6: skip the Qt 5 integration packages.
    enableQt5Integration = false;
  };
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true; # plasma6 mkDefaults this; explicit for clarity.
  };

  # Drop plasma extras we don't use (baloo/milou are required packages and get
  # disabled via config in home/kde.nix instead).
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    khelpcenter
    krdp
    kwin-x11 # sddm runs the wayland session only
    plasma-keyboard
    qtvirtualkeyboard
  ];

  # PlasmaZones needs KWin >= 6.7; nixos-26.05 ships Plasma 6.6.6.
  # Flip enable to true after the next channel rebase.
  programs.plasmazones = {
    enable = false;
    autostart = true;
  };

  qt = {
    enable = true;
    platformTheme = "kde";
    style = "breeze";
  };
}
