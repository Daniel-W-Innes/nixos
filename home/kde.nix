{
  pkgs,
  plasmaManager,
  ...
}:

{
  # Dormant: not imported by home/desktop.nix or home/laptop.nix.
  imports = [ plasmaManager.homeModules.plasma-manager ];

  home.packages = with pkgs; [
    wl-clipboard
  ];

  programs.plasma = {
    enable = true;
    shortcuts.kwin."Expose" = "Meta+,";

    # Resource minimization. Each block says what it kills and how to undo.
    configFile = {
      # Baloo is the file indexer, the biggest background CPU/RAM consumer.
      "baloofilerc"."Basic Settings"."Indexing-Enabled" = false;

      # Akonadi is the PIM backend (calendar/contacts) and runs an embedded
      # MySQL server. Hide its login autostart (a user-level autostart file
      # shadows the system one per the XDG spec) and don't start the database
      # even if something still activates the daemon.
      "autostart/org.kde.akonadi.desktop"."Desktop Entry"."Hidden" = true;
      "akonadi/akonadiserverrc"."QMYSQL"."StartServer" = false;

      # KWin: kill cosmetic effects. Compositing stays on (PlasmaZones needs
      # it); AnimationDurationFactor 0 disables animations entirely.
      "kwinrc"."KDE"."AnimationDurationFactor" = 0.5;
      "kwinrc"."Plugins" = {
        blurEnabled = false;
        wobblywindowsEnabled = false;
        magiclampEnabled = false;
        slideEnabled = false;
        fallapartEnabled = false;
      };

      # kded daemons we don't use. Module ids are the plugin basenames; the
      # config file is still kded5rc under Plasma 6.
      "kded5rc" = {
        "Module-baloosearchmodule".autoload = false; # file search over the disabled index
        "Module-org.kde.kdeconnect.daemon".autoload = false; # set true if using KDE Connect
        "Module-bluedevil".autoload = false; # bluez is not enabled on these hosts
        "Module-freespacenotifier".autoload = false; # periodic free-space checks
      };
    };
  };
}
