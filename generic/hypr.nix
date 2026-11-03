_:

{
  programs = {
    hyprland = {
      enable = true;
      # Launch the compositor through UWSM (activates graphical-session.target
      # and friends). ly gets the "Hyprland (uwsm-managed)" entry from the
      # hyprland package itself, which ships a correct uwsm desktop entry with
      # DesktopNames=Hyprland.
      withUWSM = true;
      xwayland.enable = true;
    };
    # Do NOT set uwsm.waylandCompositors: the entry it generates has the same
    # filename as hyprland's own but omits DesktopNames, and wins the
    # sessionPackages collision — ly then launches a session whose
    # XDG_CURRENT_DESKTOP looks systemd-unaware to NixOS's session wrapper,
    # which starts nixos-fake-graphical-session.target (BindsTo
    # graphical-session.target) before uwsm runs; uwsm refuses ("already
    # active!") and ly reports the login as logged out (2026-11-03).
  };
  qt = {
    enable = true;
    platformTheme = "gnome";
    style = "adwaita-dark";
  };
}
