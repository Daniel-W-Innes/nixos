import Quickshell
import QtQml

// The app launcher runs as a separate process from the bar (quickshell
// --config launcher), toggled by a hyprland keybind (quickshell kill -c
// launcher || quickshell --config launcher). One window per screen, visible
// from startup: quickshell 0.3.0 lazily builds hidden-window content and a
// ListView can skip delegate creation on the first show (see
// docs/issues/done/08-quickshell-launcher-abandoned.md).
ShellRoot {
  Variants {
    model: Quickshell.screens
    delegate: Component {
      Launcher { screen: modelData }
    }
  }
}
